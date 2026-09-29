# Remote state (recommended).
#
# DR tip: keep the state bucket OUTSIDE the primary region (or replicate it),
# otherwise a regional outage also takes away your ability to run Terraform.
#
# terraform {
#   backend "s3" {
#     bucket         = "my-tf-state-eu-west-1"
#     key            = "serverless-dr/terraform.tfstate"
#     region         = "eu-west-1"
#     dynamodb_table = "terraform-locks"
#     encrypt        = true
#   }
# }
