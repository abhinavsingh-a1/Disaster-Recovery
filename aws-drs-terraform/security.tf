# Application security group shared by the source server and the recovery
# instance (the video keeps the recovery server on the same SG as the source).
resource "aws_security_group" "app" {
  name        = "${local.name}-app"
  description = "Demo web app - source and recovery servers"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${local.name}-app-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  for_each = toset(var.http_ingress_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "HTTP to demo page"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.ssh_ingress_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "SSH admin access"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value
}

# Outbound must allow:
#   TCP 443  -> DRS service endpoint + S3 (agent control / installer download)
#   TCP 1500 -> replication servers in the staging subnet (data replication)
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.app.id
  description       = "All outbound (covers 443 to DRS and 1500 to replication servers)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# The replication-server security group (inbound TCP 1500) is created by DRS
# itself because associate_default_security_group = true in drs.tf.
