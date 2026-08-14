data "aws_iam_policy_document" "trust" {
  dynamic "statement" {
    for_each = length(var.trusted_principal_arns) > 0 ? [1] : []
    content {
      effect  = "Allow"
      actions = ["sts:AssumeRole"]
      principals {
        type        = "AWS"
        identifiers = var.trusted_principal_arns
      }
    }
  }

  # IAM rejects an Allow statement with no principals. Preserve the safe default:
  # when no trusted principal is configured, nobody can assume this role.
  dynamic "statement" {
    for_each = length(var.trusted_principal_arns) == 0 ? [1] : []
    content {
      effect  = "Deny"
      actions = ["sts:AssumeRole"]
      principals {
        type        = "AWS"
        identifiers = ["*"]
      }
    }
  }
}

resource "aws_iam_role" "break_glass" {
  name               = var.break_glass_role_name
  assume_role_policy = data.aws_iam_policy_document.trust.json
  tags               = merge(var.common_tags, { PROFILE = "BREAKING-GLASS" })
}

data "aws_iam_policy_document" "access" {
  # This deliberately remains broad enough for incident investigation; scope it further in production.
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = ["*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["rds:Describe*", "eks:Describe*"]
    resources = ["*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["sqs:*"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "break_glass_access" {
  name   = "${var.break_glass_role_name}-investigation-access"
  role   = aws_iam_role.break_glass.id
  policy = data.aws_iam_policy_document.access.json
}
