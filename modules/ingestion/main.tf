data "aws_region" "current" {}
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "archive_file" "converter" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = "${path.module}/converter.zip"
}

resource "aws_iam_role" "converter" {
  name               = "${var.name_prefix}-converter"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.common_tags
}
data "aws_iam_policy_document" "converter" {
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${var.raw_logs_bucket_arn}/*"]
  }
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${var.parquet_bucket_arn}/*"]
  }
  statement {
    actions   = ["firehose:PutRecord", "firehose:PutRecordBatch"]
    resources = [aws_kinesis_firehose_delivery_stream.breakglass.arn]
  }
}
resource "aws_iam_role_policy" "converter" {
  name   = "converter-least-privilege"
  role   = aws_iam_role.converter.id
  policy = data.aws_iam_policy_document.converter.json
}

resource "aws_lambda_function" "converter" {
  function_name    = "${var.name_prefix}-converter"
  role             = aws_iam_role.converter.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 120
  memory_size      = 1024
  filename         = data.archive_file.converter.output_path
  source_code_hash = data.archive_file.converter.output_base64sha256
  # The stream name is deterministic, avoiding a Lambda/Firehose dependency cycle.
  environment { variables = { PARQUET_BUCKET = var.parquet_bucket_name, FIREHOSE_STREAM = "${var.name_prefix}-breakglass", BREAK_GLASS_ROLE_ARN = var.break_glass_role_arn } }
  tags = var.common_tags
}

data "aws_iam_policy_document" "firehose_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "firehose" {
  name               = "${var.name_prefix}-firehose"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume.json
  tags               = var.common_tags
}
data "aws_iam_policy_document" "firehose" {
  statement {
    actions   = ["s3:AbortMultipartUpload", "s3:GetBucketLocation", "s3:GetObject", "s3:ListBucket", "s3:PutObject"]
    resources = [var.parquet_bucket_arn, "${var.parquet_bucket_arn}/*"]
  }
  statement {
    actions   = ["lambda:InvokeFunction", "lambda:GetFunctionConfiguration"]
    resources = [aws_lambda_function.converter.arn, "${aws_lambda_function.converter.arn}:$LATEST"]
  }
  statement {
    actions   = ["logs:PutLogEvents"]
    resources = ["*"]
  }
  statement {
    actions   = ["glue:GetDatabase", "glue:GetTable", "glue:GetTableVersion", "glue:GetTableVersions"]
    resources = ["*"]
  }
}
resource "aws_iam_role_policy" "firehose" {
  name   = "deliver-transformed-records"
  role   = aws_iam_role.firehose.id
  policy = data.aws_iam_policy_document.firehose.json
}

resource "aws_kinesis_firehose_delivery_stream" "breakglass" {
  name        = "${var.name_prefix}-breakglass"
  destination = "extended_s3"
  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = var.parquet_bucket_arn
    # Parquet data is isolated under data/ so Athena/Glue never scan the
    # athena-results/ or errors/ prefixes as part of the partitioned dataset.
    prefix              = "data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"
    buffering_size      = 64
    buffering_interval  = 60
    compression_format  = "UNCOMPRESSED"
    data_format_conversion_configuration {
      enabled = true
      input_format_configuration {
        deserializer {
          open_x_json_ser_de {}
        }
      }
      output_format_configuration {
        serializer {
          parquet_ser_de {
            compression = "SNAPPY"
          }
        }
      }
      schema_configuration {
        database_name = var.glue_database_name
        table_name    = var.glue_table_name
        role_arn      = aws_iam_role.firehose.arn
        region        = data.aws_region.current.name
        version_id    = "LATEST"
      }
    }
    processing_configuration {
      enabled = true
      processors {
        type = "Lambda"
        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = "${aws_lambda_function.converter.arn}:$LATEST"
        }
        parameters {
          parameter_name  = "BufferSizeInMBs"
          parameter_value = "1"
        }
        parameters {
          parameter_name  = "BufferIntervalInSeconds"
          parameter_value = "60"
        }
      }
    }
  }
  tags = var.common_tags
}

resource "aws_lambda_permission" "firehose" {
  statement_id  = "AllowFirehoseTransformation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.converter.function_name
  principal     = "firehose.amazonaws.com"
  source_arn    = aws_kinesis_firehose_delivery_stream.breakglass.arn
}
