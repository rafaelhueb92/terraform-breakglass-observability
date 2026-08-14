terraform {
  required_version = ">= 1.5"

  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}



module "iam" {
  source = "./modules/iam"

  break_glass_role_name  = var.break_glass_role_name
  trusted_principal_arns = concat(var.trusted_principal_arns, ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/admin"])
  common_tags            = local.common_tags
}

module "lake" {
  source = "./modules/lake"

  parquet_bucket_name              = "${local.name_prefix}-parquet"
  log_retention_days               = var.log_retention_days
  error_and_results_retention_days = var.error_and_results_retention_days
  enable_glue_crawler              = var.enable_glue_crawler
  common_tags                      = local.common_tags
}

module "ingestion" {
  source = "./modules/ingestion"

  name_prefix          = local.name_prefix
  raw_logs_bucket_arn  = module.cloudtrail.raw_logs_bucket_arn
  parquet_bucket_arn   = module.lake.parquet_bucket_arn
  parquet_bucket_name  = module.lake.parquet_bucket_name
  glue_database_name   = module.lake.glue_database_name
  glue_table_name      = module.lake.glue_table_name
  lambda_source_dir    = "${path.root}/lambda/converter"
  break_glass_role_arn = module.iam.role_arn
  common_tags          = local.common_tags
}

module "cloudtrail" {
  source = "./modules/cloudtrail"

  raw_logs_bucket_name = "${local.name_prefix}-cloudtrail"
  common_tags          = local.common_tags
}

# S3 cannot invoke Firehose directly. EventBridge is enabled on the raw bucket and
# invokes the converter, which reads each delivered CloudTrail object and calls Firehose.
resource "aws_cloudwatch_event_rule" "cloudtrail_object_created" {
  name = "${local.name_prefix}-cloudtrail-object-created"
  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail        = { bucket = { name = [module.cloudtrail.raw_logs_bucket_name] } }
  })
  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "converter" {
  rule = aws_cloudwatch_event_rule.cloudtrail_object_created.name
  arn  = module.ingestion.lambda_function_arn
}

resource "aws_lambda_permission" "eventbridge_to_converter" {
  statement_id  = "AllowEventBridgeCloudTrailObjects"
  action        = "lambda:InvokeFunction"
  function_name = module.ingestion.lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cloudtrail_object_created.arn
}

module "analytics" {
  source = "./modules/analytics"

  parquet_bucket_name = module.lake.parquet_bucket_name
  parquet_bucket_arn  = module.lake.parquet_bucket_arn
  glue_database_name  = module.lake.glue_database_name
  glue_table_name     = module.lake.glue_table_name
  quicksight_user     = local.quicksight_user
  common_tags         = local.common_tags
}
