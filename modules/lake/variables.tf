variable "parquet_bucket_name" { type = string }
variable "log_retention_days" { type = number }
variable "enable_glue_crawler" { type = bool }
variable "common_tags" { type = map(string) }
