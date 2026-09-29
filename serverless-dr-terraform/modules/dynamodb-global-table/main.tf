# DynamoDB global table (version 2019.11.21) = a normal aws_dynamodb_table
# with one or more `replica` blocks. The table in the provider's region is the
# first replica; every `replica` block adds another region.
#
# Requirements mirrored from the talk:
#  - Streams MUST be enabled with NEW_AND_OLD_IMAGES (replication rides on them)
#  - Same table name in every region
#  - Deployed ONCE, not once per region

resource "aws_dynamodb_table" "this" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  # Active/active does NOT protect against bad writes or data corruption:
  # a bad write is replicated everywhere within ~1s. PITR is the safety net.
  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  dynamic "replica" {
    for_each = toset(var.replica_regions)
    content {
      region_name            = replica.value
      point_in_time_recovery = true
      propagate_tags         = true
    }
  }

  deletion_protection_enabled = var.deletion_protection

  tags = {
    Name = var.table_name
  }
}
