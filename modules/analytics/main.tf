data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_athena_workgroup" "breakglass" {
  name = "breakglass-analytics"
  configuration {
    enforce_workgroup_configuration = true
    result_configuration { output_location = "s3://${var.parquet_bucket_name}/athena-results/" }
  }
  tags = var.common_tags
}

locals {
  table = "${var.glue_database_name}.${var.glue_table_name}"
  queries = {
    top_apis        = "SELECT eventname, eventsource, count(*) AS api_calls FROM ${local.table} GROUP BY eventname, eventsource ORDER BY api_calls DESC LIMIT 20"
    daily_usage     = "WITH daily AS (SELECT date(eventtime) AS day, count(DISTINCT sessionarn) AS sessions, count(*) AS api_calls FROM ${local.table} GROUP BY 1) SELECT day, sessions, api_calls, avg(api_calls) OVER (ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS api_calls_7d_avg FROM daily ORDER BY day"
    unique_users    = "SELECT username, min(eventtime) AS first_seen, max(eventtime) AS last_seen, count(*) AS api_calls FROM ${local.table} GROUP BY username ORDER BY last_seen DESC"
    service_heatmap = "SELECT eventsource, eventname, count(*) AS api_calls FROM ${local.table} WHERE from_iso8601_timestamp(eventtime) >= current_timestamp - interval '30' day GROUP BY eventsource, eventname ORDER BY api_calls DESC"
  }
}
resource "aws_athena_named_query" "queries" {
  for_each  = local.queries
  name      = each.key
  workgroup = aws_athena_workgroup.breakglass.name
  database  = var.glue_database_name
  query     = each.value
}

# QuickSight resources are created in the account's QuickSight home Region.
resource "aws_quicksight_data_source" "athena" {
  aws_account_id = data.aws_caller_identity.current.account_id
  data_source_id = "breakglass-athena"
  name           = "BreakGlass Athena"
  type           = "ATHENA"
  data_source_parameters {
    athena_parameters { work_group = aws_athena_workgroup.breakglass.name }
  }
  permissions {
    principal = var.quicksight_user_arn
    actions   = ["quicksight:DescribeDataSource", "quicksight:DescribeDataSourcePermissions", "quicksight:PassDataSource", "quicksight:UpdateDataSource", "quicksight:DeleteDataSource", "quicksight:UpdateDataSourcePermissions"]
  }
  tags = var.common_tags
}
resource "aws_quicksight_data_set" "top_apis" {
  aws_account_id = data.aws_caller_identity.current.account_id
  data_set_id    = "breakglass-top-apis"
  name           = "BreakGlass Top APIs"
  import_mode    = "DIRECT_QUERY"
  physical_table_map {
    physical_table_map_id = "topApis"
    custom_sql {
      data_source_arn = aws_quicksight_data_source.athena.arn
      name            = "top_apis"
      sql_query       = local.queries.top_apis
      columns {
        name = "eventname"
        type = "STRING"
      }
      columns {
        name = "eventsource"
        type = "STRING"
      }
      columns {
        name = "api_calls"
        type = "INTEGER"
      }
    }
  }
  permissions {
    principal = var.quicksight_user_arn
    actions   = ["quicksight:DescribeDataSet", "quicksight:DescribeDataSetPermissions", "quicksight:PassDataSet", "quicksight:DescribeIngestion", "quicksight:ListIngestions", "quicksight:UpdateDataSet", "quicksight:DeleteDataSet", "quicksight:UpdateDataSetPermissions"]
  }
  tags = var.common_tags
}
