# Remote state in S3 with native locking. Values come from backend.hcl
# (see backend.hcl.example and the bootstrap/ stack):
#   terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {}
}
