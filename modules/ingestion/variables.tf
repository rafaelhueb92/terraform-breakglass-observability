variable "name_prefix" { type = string }
variable "raw_logs_bucket_arn" { type = string }
variable "parquet_bucket_arn" { type = string }
variable "parquet_bucket_name" { type = string }
variable "lambda_source_dir" { type = string }
variable "break_glass_role_arn" { type = string }
variable "common_tags" { type = map(string) }
