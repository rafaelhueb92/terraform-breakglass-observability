locals {
  # Keep names predictable for a lab while account ID prevents cross-account collisions.
  name_prefix     = "${var.prefix}-${data.aws_caller_identity.current.account_id}"
  quicksight_user = "arn:aws:quicksight:${var.aws_region}:${data.aws_caller_identity.current.account_id}:user/default/${var.quicksight_user}"
  common_tags = {
    ManagedBy   = "Terraform"
    Project     = "BreakGlassObservability"
    Environment = "lab"
  }
}
