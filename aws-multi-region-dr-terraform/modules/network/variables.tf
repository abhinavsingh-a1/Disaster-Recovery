variable "name" {
  description = "Name prefix."
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block (/16 recommended)."
  type        = string
}

variable "az_count" {
  description = "Number of Availability Zones to span."
  type        = number
  default     = 2
}

variable "enable_nat_gateway" {
  description = "Create a NAT gateway so private web instances can reach package repositories and AWS APIs."
  type        = bool
  default     = true
}
