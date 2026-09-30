variable "name" {
  description = "Name prefix (<= 28 characters so ALB/target group names stay within 32)."
  type        = string
}

variable "project_name" {
  description = "Project name shown by the app."
  type        = string
}

variable "site_role" {
  description = "primary or dr - reported by the app so you can see which region answered."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "alb_subnet_ids" {
  description = "Public subnets for the ALB."
  type        = list(string)
}

variable "instance_subnet_ids" {
  description = "Private subnets for the web instances."
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
}

variable "min_size" {
  description = "ASG minimum size."
  type        = number
}

variable "desired_capacity" {
  description = "ASG desired capacity at creation (afterwards owned by scaling)."
  type        = number
}

variable "max_size" {
  description = "ASG maximum size."
  type        = number
}

variable "enable_https" {
  description = "Create an HTTPS listener and redirect HTTP to HTTPS (requires certificate_arn)."
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ACM certificate ARN in this region. Used only when enable_https is true."
  type        = string
  default     = null
}

variable "alb_deletion_protection" {
  description = "Enable ALB deletion protection."
  type        = bool
  default     = false
}

variable "app_source" {
  description = "Source code of the Python web app (app/app.py)."
  type        = string
}

variable "db_host" {
  description = "Aurora cluster endpoint in this region."
  type        = string
}

variable "db_secret_name" {
  description = "Secrets Manager secret name holding username, password and dbname (readable in this region)."
  type        = string
}

variable "write_forwarding" {
  description = "Whether the regional Aurora cluster uses global write forwarding (multi_site DR)."
  type        = bool
  default     = false
}

variable "alarm_topic_arn" {
  description = "SNS topic in this region for alarm notifications."
  type        = string
}
