resource "aws_s3_bucket" "parquet" {
  bucket        = var.parquet_bucket_name
  force_destroy = true
  lifecycle { prevent_destroy = false }
  tags = var.common_tags
}

resource "aws_s3_bucket_public_access_block" "parquet" {
  bucket                  = aws_s3_bucket.parquet.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "parquet" {
  bucket = aws_s3_bucket.parquet.id
  rule {
    id     = "lab-retention"
    status = "Enabled"
    filter {}
    # Observability data is useful briefly in a lab; expiration prevents silent cost growth.
    expiration { days = var.log_retention_days }
  }
}

resource "aws_glue_catalog_database" "breakglass" {
  name        = "breakglass_db"
  description = "Break-glass CloudTrail records stored as Parquet."
  tags        = var.common_tags
}

resource "aws_glue_catalog_table" "cloudtrail_breakglass" {
  name          = "cloudtrail_breakglass"
  database_name = aws_glue_catalog_database.breakglass.name
  table_type    = "EXTERNAL_TABLE"
  parameters    = { EXTERNAL = "TRUE", "parquet.compression" = "SNAPPY" }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.parquet.bucket}/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
    ser_de_info { serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe" }
    dynamic "columns" {
      for_each = {
        eventtime  = "string", eventname = "string", eventsource = "string", username = "string"
        sessionarn = "string", sourceipaddress = "string", requestparameters = "string", errorcode = "string"
      }
      content {
        name = columns.key
        type = columns.value
      }
    }
  }
  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
}

data "aws_iam_policy_document" "crawler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}
resource "aws_iam_role" "crawler" {
  name               = "breakglass-glue-crawler-role"
  assume_role_policy = data.aws_iam_policy_document.crawler_assume.json
  tags               = var.common_tags
}
resource "aws_iam_role_policy_attachment" "crawler_service" {
  role       = aws_iam_role.crawler.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSGlueServiceRole"
}
data "aws_partition" "current" {}
data "aws_iam_policy_document" "crawler_s3" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.parquet.arn]
  }
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.parquet.arn}/*"]
  }
}
resource "aws_iam_role_policy" "crawler_s3" {
  name   = "read-breakglass-parquet"
  role   = aws_iam_role.crawler.id
  policy = data.aws_iam_policy_document.crawler_s3.json
}

resource "aws_glue_crawler" "breakglass" {
  count         = var.enable_glue_crawler ? 1 : 0
  name          = "breakglass-cloudtrail-crawler"
  database_name = aws_glue_catalog_database.breakglass.name
  role          = aws_iam_role.crawler.arn
  schedule      = "cron(0 1 * * ? *)"
  s3_target { path = "s3://${aws_s3_bucket.parquet.bucket}/" }
  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }
  tags = var.common_tags
}
