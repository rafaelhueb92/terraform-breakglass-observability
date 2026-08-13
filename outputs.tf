output "break_glass_role_arn" { value = module.iam.role_arn }
output "raw_logs_bucket_name" { value = module.cloudtrail.raw_logs_bucket_name }
output "firehose_stream_arn" { value = module.ingestion.firehose_stream_arn }
output "parquet_bucket_name" { value = module.lake.parquet_bucket_name }
output "glue_database_name" { value = module.lake.glue_database_name }
output "athena_workgroup_name" { value = module.analytics.athena_workgroup_name }
output "quicksight_dataset_arn" { value = module.analytics.quicksight_dataset_arn }
