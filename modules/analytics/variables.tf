variable "parquet_bucket_name" { type = string }
variable "parquet_bucket_arn" { type = string }
variable "glue_database_name" { type = string }
variable "glue_table_name" { type = string }
variable "quicksight_user_arn" { type = string }
variable "common_tags" { type = map(string) }
