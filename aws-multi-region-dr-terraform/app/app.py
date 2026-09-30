#!/usr/bin/env python3
"""DR demo web app.

A deliberately small notes service that proves disaster recovery works:
data written in one region must still be readable after failing over to the
other. Standard library plus PyMySQL only, so it installs in seconds.

Endpoints
  GET  /                  HTML page: region, role, database status, latest notes
  GET  /health/live       200 while the process runs (ALB target health)
  GET  /health            200 only if the database answers (Route 53 health check)
  GET  /api/whoami        JSON: which region / instance / database answered
  GET  /api/notes         JSON: latest 20 notes
  GET  /api/notes/<id>    JSON: one note, 404 if missing (used by the DR drill to measure RPO)
  POST /api/notes         JSON {"text": "..."} -> {"id": n}; 503 while the region is read-only
"""
import html
import json
import os
import re
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pymysql

CONFIG_PATH = os.environ.get("DR_APP_CONFIG", "/etc/dr-app/config.json")
SECRET_PATH = os.environ.get("DR_APP_SECRET", "/etc/dr-app/db-secret.json")
PORT = int(os.environ.get("DR_APP_PORT", "80"))

# MySQL error codes that mean "this cluster cannot take writes right now"
READ_ONLY_ERRORS = {1290, 1836, 1792}
TABLE_MISSING = 1146

SCHEMA = """
CREATE TABLE IF NOT EXISTS notes (
  id          BIGINT AUTO_INCREMENT PRIMARY KEY,
  body        VARCHAR(500) NOT NULL,
  region      VARCHAR(32)  NOT NULL,
  created_at  TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
)
"""


def load_json(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def instance_identity():
    """Instance ID and AZ from IMDSv2; falls back gracefully off EC2."""
    try:
        token_req = urllib.request.Request(
            "http://169.254.169.254/latest/api/token",
            method="PUT",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "300"},
        )
        token = urllib.request.urlopen(token_req, timeout=1).read().decode()
        headers = {"X-aws-ec2-metadata-token": token}

        def get(path):
            req = urllib.request.Request(
                "http://169.254.169.254/latest/meta-data/" + path, headers=headers)
            return urllib.request.urlopen(req, timeout=1).read().decode()

        return get("instance-id"), get("placement/availability-zone")
    except OSError:
        return "local", "local"


class Database:
    def __init__(self, config, secret):
        self.config = config
        self.secret = secret

    def connect(self):
        conn = pymysql.connect(
            host=self.config["db_host"],
            user=self.secret["username"],
            password=self.secret["password"],
            database=self.secret["dbname"],
            connect_timeout=3,
            read_timeout=5,
            write_timeout=5,
            autocommit=True,
            cursorclass=pymysql.cursors.DictCursor,
        )
        if self.config.get("write_forwarding"):
            # Global write forwarding: read your own writes within the session
            try:
                with conn.cursor() as cur:
                    cur.execute("SET aurora_replica_read_consistency = 'SESSION'")
            except pymysql.MySQLError:
                pass
        return conn

    def status(self):
        """(reachable, writable, error)"""
        try:
            conn = self.connect()
            try:
                with conn.cursor() as cur:
                    cur.execute("SELECT @@innodb_read_only AS ro")
                    read_only = bool(cur.fetchone()["ro"])
            finally:
                conn.close()
            return True, not read_only, None
        except pymysql.MySQLError as exc:
            return False, False, str(exc)

    def insert_note(self, text, region):
        conn = self.connect()
        try:
            with conn.cursor() as cur:
                try:
                    cur.execute("INSERT INTO notes (body, region) VALUES (%s, %s)", (text, region))
                except pymysql.MySQLError as exc:
                    if exc.args and exc.args[0] == TABLE_MISSING:
                        cur.execute(SCHEMA)
                        cur.execute("INSERT INTO notes (body, region) VALUES (%s, %s)", (text, region))
                    else:
                        raise
                return cur.lastrowid
        finally:
            conn.close()

    def _query(self, sql, args=()):
        conn = self.connect()
        try:
            with conn.cursor() as cur:
                try:
                    cur.execute(sql, args)
                except pymysql.MySQLError as exc:
                    if exc.args and exc.args[0] == TABLE_MISSING:
                        return []  # nothing written yet
                    raise
                return cur.fetchall()
        finally:
            conn.close()

    def latest_notes(self, limit=20):
        return self._query(
            "SELECT id, body, region, created_at FROM notes ORDER BY id DESC LIMIT %s", (limit,))

    def get_note(self, note_id):
        rows = self._query("SELECT id, body, region, created_at FROM notes WHERE id = %s", (note_id,))
        return rows[0] if rows else None


def serialize(row):
    out = dict(row)
    if "created_at" in out and hasattr(out["created_at"], "isoformat"):
        out["created_at"] = out["created_at"].isoformat()
    return out


class Handler(BaseHTTPRequestHandler):
    server_version = "dr-app/1.0"
    db = None
    config = {}
    identity = ("local", "local")

    # ----------------------------------------------------------- helpers
    def _send(self, status, body, content_type="application/json"):
        data = body if isinstance(body, bytes) else body.encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _json(self, status, obj):
        self._send(status, json.dumps(obj, default=str))

    def _whoami(self):
        reachable, writable, error = self.db.status()
        return {
            "project": self.config["project"],
            "site_role": self.config["site_role"],
            "region": self.config["region"],
            "instance_id": self.identity[0],
            "availability_zone": self.identity[1],
            "db_endpoint": self.config["db_host"],
            "db_reachable": reachable,
            "db_writable": writable,
            "db_error": error,
            "write_forwarding": bool(self.config.get("write_forwarding")),
            "time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }

    def log_message(self, fmt, *args):  # quieter logs: skip health checks
        if not self.path.startswith("/health"):
            super().log_message(fmt, *args)

    # ----------------------------------------------------------- routes
    def do_GET(self):  # noqa: N802 (stdlib naming)
        path = self.path.split("?", 1)[0]
        if path == "/health/live":
            return self._send(200, "OK", "text/plain")
        if path == "/health":
            reachable, _, error = self.db.status()
            return self._send(200 if reachable else 503, "OK" if reachable else f"DB: {error}", "text/plain")
        if path == "/api/whoami":
            return self._json(200, self._whoami())
        if path == "/api/notes":
            try:
                return self._json(200, [serialize(r) for r in self.db.latest_notes()])
            except pymysql.MySQLError as exc:
                return self._json(503, {"error": str(exc)})
        match = re.fullmatch(r"/api/notes/(\d+)", path)
        if match:
            try:
                row = self.db.get_note(int(match.group(1)))
            except pymysql.MySQLError as exc:
                return self._json(503, {"error": str(exc)})
            return self._json(200, serialize(row)) if row else self._json(404, {"error": "not found"})
        if path == "/":
            return self._send(200, self._page(), "text/html; charset=utf-8")
        return self._json(404, {"error": "not found"})

    def do_POST(self):  # noqa: N802
        if self.path.split("?", 1)[0] != "/api/notes":
            return self._json(404, {"error": "not found"})
        try:
            length = min(int(self.headers.get("Content-Length", "0")), 10_000)
            payload = json.loads(self.rfile.read(length) or b"{}")
            text = str(payload.get("text", "")).strip()[:500]
        except (ValueError, AttributeError):
            return self._json(400, {"error": "send JSON like {\"text\": \"hello\"}"})
        if not text:
            return self._json(400, {"error": "text is required"})
        try:
            note_id = self.db.insert_note(text, self.config["region"])
        except pymysql.MySQLError as exc:
            code = exc.args[0] if exc.args else None
            if code in READ_ONLY_ERRORS:
                return self._json(503, {"error": "database is read-only in this region (not promoted yet)"})
            return self._json(503, {"error": str(exc)})
        return self._json(201, {"id": note_id, "region": self.config["region"]})

    # ----------------------------------------------------------- page
    def _page(self):
        info = self._whoami()
        try:
            notes = self.db.latest_notes(10)
        except pymysql.MySQLError:
            notes = []
        esc = html.escape
        rows = "".join(
            f"<tr><td>{n['id']}</td><td>{esc(n['body'])}</td><td>{esc(n['region'])}</td>"
            f"<td>{esc(str(n['created_at']))}</td></tr>" for n in notes
        ) or "<tr><td colspan='4'>No notes yet.</td></tr>"
        db_state = ("read/write" if info["db_writable"] else "read-only") if info["db_reachable"] else "unreachable"
        return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(info['project'])} - {esc(info['site_role'])}</title>
<style>
 body {{ font-family: system-ui, sans-serif; max-width: 46rem; margin: 2rem auto; padding: 0 1rem; color: #1f2d3d; }}
 .site {{ padding: .8rem 1rem; border-radius: 6px; background: {'#eef4fb' if info['site_role'] == 'primary' else '#fdf2e9'}; }}
 table {{ border-collapse: collapse; width: 100%; margin-top: 1rem; }}
 td, th {{ border-bottom: 1px solid #dde3ea; padding: .4rem; text-align: left; font-size: .92rem; }}
 input {{ padding: .45rem; width: 70%; }} button {{ padding: .45rem .9rem; }}
</style></head><body>
<div class="site"><h1>Served by the {esc(info['site_role'])} site</h1>
<p>Region <b>{esc(info['region'])}</b>, instance {esc(info['instance_id'])} ({esc(info['availability_zone'])})<br>
Database in this region: <b>{db_state}</b></p></div>
<p><input id="t" placeholder="Write a note, then fail over and look for it"> <button onclick="add()">Save note</button>
<span id="msg"></span></p>
<table><tr><th>ID</th><th>Note</th><th>Written in</th><th>At (UTC)</th></tr>{rows}</table>
<script>
async function add() {{
  const r = await fetch('/api/notes', {{method: 'POST', headers: {{'Content-Type': 'application/json'}},
    body: JSON.stringify({{text: document.getElementById('t').value}})}});
  const j = await r.json();
  document.getElementById('msg').textContent = r.ok ? 'Saved' : j.error;
  if (r.ok) location.reload();
}}
</script></body></html>"""


def main():
    config = load_json(CONFIG_PATH)
    secret = load_json(SECRET_PATH)
    Handler.config = config
    Handler.db = Database(config, secret)
    Handler.identity = instance_identity()
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
