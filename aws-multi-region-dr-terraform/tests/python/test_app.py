"""Unit tests for app/app.py HTTP routes, with a fake database and a stub pymysql module."""
import io
import json
import os
import sys
import types
import unittest

# Stub pymysql so the tests run without the real driver
fake_pymysql = types.ModuleType("pymysql")


class MySQLError(Exception):
    pass


fake_pymysql.MySQLError = MySQLError
fake_pymysql.cursors = types.SimpleNamespace(DictCursor=object)
fake_pymysql.connect = lambda **kw: None
sys.modules.setdefault("pymysql", fake_pymysql)

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "app"))
import app  # noqa: E402


class FakeDb:
    def __init__(self, reachable=True, writable=True):
        self.reachable = reachable
        self.writable = writable
        self.notes = {}

    def status(self):
        return self.reachable, self.writable, None if self.reachable else "down"

    def insert_note(self, text, region):
        if not self.writable:
            raise app.pymysql.MySQLError(1290, "read only")
        note_id = len(self.notes) + 1
        self.notes[note_id] = {"id": note_id, "body": text, "region": region, "created_at": "now"}
        return note_id

    def latest_notes(self, limit=20):
        return list(self.notes.values())[-limit:]

    def get_note(self, note_id):
        return self.notes.get(note_id)


def call(db, method, path, body=None):
    """Drive the handler without a socket."""
    h = app.Handler.__new__(app.Handler)
    h.db = db
    h.config = {"project": "t", "site_role": "dr", "region": "eu-west-1", "db_host": "db", "write_forwarding": False}
    h.identity = ("i-1", "eu-west-1a")
    h.path = path
    raw = json.dumps(body).encode() if body is not None else b""
    h.headers = {"Content-Length": str(len(raw))}
    h.rfile = io.BytesIO(raw)
    h.wfile = io.BytesIO()
    sent = {}
    h.send_response = lambda code: sent.setdefault("status", code)
    h.send_header = lambda *a: None
    h.end_headers = lambda: None
    getattr(h, "do_" + method)()
    return sent["status"], h.wfile.getvalue().decode()


class AppTests(unittest.TestCase):
    def test_liveness_ignores_database(self):
        self.assertEqual(call(FakeDb(reachable=False), "GET", "/health/live")[0], 200)

    def test_deep_health_fails_without_database(self):
        self.assertEqual(call(FakeDb(reachable=False), "GET", "/health")[0], 503)
        self.assertEqual(call(FakeDb(), "GET", "/health")[0], 200)

    def test_write_then_read_note(self):
        db = FakeDb()
        status, body = call(db, "POST", "/api/notes", {"text": "drill marker"})
        self.assertEqual(status, 201)
        note_id = json.loads(body)["id"]
        status, body = call(db, "GET", f"/api/notes/{note_id}")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["body"], "drill marker")

    def test_read_only_region_rejects_writes_with_503(self):
        status, body = call(FakeDb(writable=False), "POST", "/api/notes", {"text": "x"})
        self.assertEqual(status, 503)
        self.assertIn("read-only", json.loads(body)["error"])

    def test_missing_note_is_404(self):
        self.assertEqual(call(FakeDb(), "GET", "/api/notes/99")[0], 404)

    def test_empty_text_is_400(self):
        self.assertEqual(call(FakeDb(), "POST", "/api/notes", {"text": " "})[0], 400)

    def test_whoami_reports_region_and_db_state(self):
        status, body = call(FakeDb(writable=False), "GET", "/api/whoami")
        info = json.loads(body)
        self.assertEqual(status, 200)
        self.assertEqual(info["region"], "eu-west-1")
        self.assertFalse(info["db_writable"])

    def test_page_renders(self):
        db = FakeDb()
        call(db, "POST", "/api/notes", {"text": "<script>"})
        status, body = call(db, "GET", "/")
        self.assertEqual(status, 200)
        self.assertIn("&lt;script&gt;", body)  # escaped


if __name__ == "__main__":
    unittest.main()
