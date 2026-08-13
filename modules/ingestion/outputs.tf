output "firehose_stream_arn" { value = aws_kinesis_firehose_delivery_stream.breakglass.arn }
output "firehose_stream_name" { value = aws_kinesis_firehose_delivery_stream.breakglass.name }
output "lambda_function_arn" { value = aws_lambda_function.converter.arn }
output "lambda_function_name" { value = aws_lambda_function.converter.function_name }
