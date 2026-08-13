data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

resource "aws_s3_bucket" "raw_logs" {
  bucket        = var.raw_logs_bucket_name
  force_destroy = true
  # Explicitly false keeps a lab destroyable while still documenting the intentional choice.
  lifecycle { prevent_destroy = false }
  tags = var.common_tags
}

resource "aws_s3_bucket_public_access_block" "raw_logs" {
  bucket                  = aws_s3_bucket.raw_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "raw_logs" {
  bucket = aws_s3_bucket.raw_logs.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

data "aws_iam_policy_document" "cloudtrail_bucket" {
  statement {
    sid = "CloudTrailAclCheck"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.raw_logs.arn]
  }
  statement {
    sid = "CloudTrailWrite"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.raw_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "raw_logs" {
  bucket = aws_s3_bucket.raw_logs.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket.json
}

resource "aws_s3_bucket_notification" "eventbridge" {
  bucket      = aws_s3_bucket.raw_logs.id
  eventbridge = true
}

resource "aws_cloudtrail" "breakglass" {
  name                          = "${var.raw_logs_bucket_name}-trail"
  s3_bucket_name                = aws_s3_bucket.raw_logs.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_logging                = true
  depends_on                    = [aws_s3_bucket_policy.raw_logs]
  event_selector {
    read_write_type           = "All"
    include_management_events = true
    data_resource {
      type = "AWS::S3::Object"
      # Use the current partition so the module remains portable beyond commercial AWS.
      values = ["arn:${data.aws_partition.current.partition}:s3"]
    }
  }
  tags = var.common_tags
}
