variable "parquet_bucket_name" { type = string }
variable "log_retention_days" { type = number }
variable "error_and_results_retention_days" {
  description = "Retention in days for operational artifacts (errors/ and athena-results/)."
  type        = number
  default     = 30
}
variable "enable_glue_crawler" { type = bool }
variable "common_tags" { type = map(string) }
