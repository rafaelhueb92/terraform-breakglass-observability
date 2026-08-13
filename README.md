# terraform-breakglass-observability 🔭

![Terraform](https://img.shields.io/badge/Terraform-1.5%2B-844FBA?logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-CloudTrail%20%7C%20Athena%20%7C%20QuickSight-FF9900?logo=amazonaws&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)

A compact AWS lab for detecting, retaining, and querying CloudTrail actions made through a break-glass role. It provisions the emergency role, a regional CloudTrail trail, a filtered Parquet lake, Glue/Athena analytics, and a QuickSight dataset in one apply. 🚨

## Prerequisites ✅

- Terraform 1.5 or later and AWS credentials with permissions to create the listed IAM, S3, CloudTrail, Lambda, Firehose, Glue, Athena, EventBridge, and QuickSight resources.
- An existing, subscribed QuickSight user in the same AWS account. Set its ARN in `quicksight_user_arn`.
- Python dependencies bundled for Lambda before applying. `archive_file` only archives files; it cannot compile pyarrow's native libraries. From `lambda/converter`, run `pip install -r requirements.txt -t .` using an Amazon Linux-compatible build environment, or replace it with an appropriate pyarrow Lambda layer.

## Quick start 🚀

```bash
terraform init
terraform apply -var='quicksight_user_arn=<existing-QuickSight-user-ARN>'
```

To avoid malformed local Lambda packages, build dependencies first as noted above. S3 buckets use `force_destroy = true` and `prevent_destroy = false`, so `terraform destroy` cleans up lab objects as well as resources.

## Architecture 🏗️

```text
Trusted principals
       |
       v
BreakGlassRole -- CloudTrail management + S3 data events --> raw CloudTrail S3
                                                            |
                                                        EventBridge
                                                            |
                                                            v
                                                     converter Lambda
                                                            |
                                                       Firehose
                                                            |
                                                            v
                  Glue crawler --> Glue catalog <-- partitioned Parquet S3
                                              |
                                      Athena workgroup / named queries
                                              |
                                      QuickSight data source + dataset
```

## Variables ⚙️ ⚙️

| Name                     | Type         | Default          | Description                                                   |
| ------------------------ | ------------ | ---------------- | ------------------------------------------------------------- |
| `aws_region`             | string       | `us-east-1`      | Deployment Region.                                            |
| `prefix`                 | string       | `breakglass`     | Resource-name prefix; account ID is appended to bucket names. |
| `break_glass_role_name`  | string       | `BreakGlassRole` | Emergency role to create and detect.                          |
| `trusted_principal_arns` | list(string) | `[]`             | Principals allowed to assume it.                              |
| `log_retention_days`     | number       | `90`             | Parquet lifecycle expiration.                                 |
| `quicksight_user_arn`    | string       | required         | Existing QuickSight user ARN.                                 |
| `enable_glue_crawler`    | bool         | `true`           | Enable daily partition discovery.                             |

## Example Athena queries

```sql
SELECT eventname, eventsource, count(*) AS calls
FROM breakglass_db.cloudtrail_breakglass
GROUP BY 1, 2 ORDER BY calls DESC LIMIT 20;

SELECT username, min(eventtime) first_seen, max(eventtime) last_seen
FROM breakglass_db.cloudtrail_breakglass
GROUP BY username;
```

The saved queries include `top_apis`, `daily_usage`, `unique_users`, and `service_heatmap`.

## Lab cost

At low personal-lab volume this should be near-zero: S3 storage and Athena scans remain tiny, Lambda/Firehose stay within or close to free-tier usage, and CloudTrail management-event logging is free for the first trail. S3 data events, Firehose ingestion, Glue crawler DPU time, Athena bytes scanned, and QuickSight can incur charges; the daily crawler and a paid QuickSight edition are normally the largest surprises. Check current regional pricing before extended use.
