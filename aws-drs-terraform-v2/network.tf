module "network_primary" {
  source = "./modules/network"

  name                  = "${local.name}-prod"
  cidr                  = var.primary_vpc_cidr
  azs                   = local.primary_azs
  create_nat_gateway    = true
  create_staging_subnet = !local.same_region # staging area for failback replication
  enable_vpc_endpoints  = false
  enable_flow_logs      = var.enable_flow_logs
}

module "network_dr" {
  source    = "./modules/network"
  providers = { aws = aws.dr }

  name                  = "${local.name}-dr"
  cidr                  = var.dr_vpc_cidr
  azs                   = local.dr_azs
  create_nat_gateway    = var.dr_enable_nat_gateway
  create_staging_subnet = true
  enable_vpc_endpoints  = var.dr_enable_vpc_endpoints
  enable_flow_logs      = var.enable_flow_logs
}

# Private replication path (TCP 1500) between production and recovery VPCs.
resource "aws_vpc_peering_connection" "prod_dr" {
  vpc_id      = module.network_primary.vpc_id
  peer_vpc_id = module.network_dr.vpc_id
  peer_region = local.dr_region
  auto_accept = false
  tags        = { Name = "${local.name}-prod-to-dr" }
}

resource "aws_vpc_peering_connection_accepter" "dr" {
  provider                  = aws.dr
  vpc_peering_connection_id = aws_vpc_peering_connection.prod_dr.id
  auto_accept               = true
  tags                      = { Name = "${local.name}-prod-to-dr" }
}

resource "aws_route" "primary_to_dr" {
  route_table_id            = module.network_primary.private_route_table_id
  destination_cidr_block    = var.dr_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.prod_dr.id
  depends_on                = [aws_vpc_peering_connection_accepter.dr]
}

resource "aws_route" "dr_to_primary" {
  provider                  = aws.dr
  route_table_id            = module.network_dr.private_route_table_id
  destination_cidr_block    = var.primary_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.prod_dr.id
  depends_on                = [aws_vpc_peering_connection_accepter.dr]
}
