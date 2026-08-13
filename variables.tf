variable "aws_region" {
  description = "AWS region in which to create the lab resources."
  type        = string
  default     = "us-east-1"
}

variable "prefix" {
  description = "Prefix used for resource names. The AWS account ID is appended to S3 bucket names."
  type        = string
  default     = "breakglass"
}

variable "break_glass_role_name" {
  description = "Name of the emergency-access role to observe."
  type        = string
  default     = "BreakGlassRole"
}

variable "trusted_principal_arns" {
  description = "IAM principal ARNs permitted to assume the break-glass role. Empty means no principals can assume it."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Number of days to retain Parquet observations."
  type        = number
  default     = 90
  validation {
    condition     = var.log_retention_days >= 1
    error_message = "log_retention_days must be at least one day."
  }
}

variable "quicksight_user_arn" {
  description = "ARN of an existing QuickSight user that will own and query the dataset."
  type        = string
}

variable "enable_glue_crawler" {
  description = "Whether to run the daily crawler that discovers new S3 partitions."
  type        = bool
  default     = true
}
