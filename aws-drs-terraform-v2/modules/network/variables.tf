variable "name" {
  description = "Name prefix."
  type        = string
}

variable "cidr" {
  description = "VPC CIDR (/16 recommended)."
  type        = string
}

variable "azs" {
  description = "Exactly two availability zones."
  type        = list(string)

  validation {
    condition     = length(var.azs) == 2
    error_message = "Provide exactly two AZs."
  }
}

variable "create_nat_gateway" {
  description = "Single NAT gateway for private subnets."
  type        = bool
}

variable "create_staging_subnet" {
  description = "Create a dedicated private subnet for the DRS staging area."
  type        = bool
}

variable "enable_vpc_endpoints" {
  description = "Create interface endpoints + S3 gateway endpoint."
  type        = bool
}

variable "interface_endpoints" {
  description = "Interface endpoint service short names."
  type        = list(string)
  default     = ["drs", "ec2", "sts", "ssm", "ssmmessages", "ec2messages", "secretsmanager", "logs"]
}

variable "enable_flow_logs" {
  description = "VPC flow logs to CloudWatch Logs."
  type        = bool
}
