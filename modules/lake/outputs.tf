output "parquet_bucket_name" { value = aws_s3_bucket.parquet.bucket }
output "parquet_bucket_arn" { value = aws_s3_bucket.parquet.arn }
output "glue_database_name" { value = aws_glue_catalog_database.breakglass.name }
output "glue_table_name" { value = aws_glue_catalog_table.cloudtrail_breakglass.name }
