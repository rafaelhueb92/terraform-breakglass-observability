output "raw_logs_bucket_name" { value = aws_s3_bucket.raw_logs.bucket }
output "raw_logs_bucket_arn" { value = aws_s3_bucket.raw_logs.arn }
output "trail_arn" { value = aws_cloudtrail.breakglass.arn }
