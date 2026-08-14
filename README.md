# terraform-breakglass-observability 🔭

![Terraform](https://img.shields.io/badge/Terraform-1.5%2B-844FBA?logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-CloudTrail%20%7C%20Athena%20%7C%20QuickSight-FF9900?logo=amazonaws&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)

A compact AWS lab for detecting, retaining, and querying CloudTrail actions made through a break-glass role. It provisions the emergency role, a regional CloudTrail trail, a filtered Parquet lake, Glue/Athena analytics, and a QuickSight dataset in one apply. 🚨

## Prerequisites ✅

- Terraform 1.5 or later and AWS credentials with permissions to create the listed IAM, S3, CloudTrail, Lambda, Firehose, Glue, Athena, EventBridge, and QuickSight resources.
- An existing, subscribed QuickSight user in the same AWS account. Set its username in `quicksight_user`.
- The Lambda uses only the Python standard library and the AWS SDK bundled with the Lambda runtime. Kinesis Firehose performs the JSON-to-Parquet conversion using the managed Glue schema, so no Docker image or dependency layer is required.

## Quick start 🚀

```bash
terraform init \
  -backend-config='bucket=<terraform-state-bucket>' \
  -backend-config='key=breakglass-observability/terraform.tfstate' \
  -backend-config='region=us-east-1' \
  -backend-config='encrypt=true'
terraform apply -var='quicksight_user=<existing-QuickSight-username>'
```

S3 buckets use `force_destroy = true` and `prevent_destroy = false`, so `terraform destroy` cleans up lab objects as well as resources.

The backend bucket must already exist. The GitHub Actions workflow supplies these backend values automatically from the `TF_STATE_BUCKET` repository variable.

## GitHub Actions

The repository workflow runs Terraform using GitHub Actions OIDC. Configure the following GitHub settings:

- Secret `AWS_ROLE_TO_ASSUME`: ARN of an IAM role trusted by GitHub's OIDC provider.
- Variable `AWS_REGION`: deployment region, such as `us-east-1`.
- Variable `TF_STATE_BUCKET`: pre-existing S3 bucket for the Terraform state. It can also be configured as a secret; if omitted, the workflow derives `breakglass-<AWS_ACCOUNT_ID>` from the `AWS_ACCOUNT_ID` secret.
- Variable `TF_STATE_KEY`: optional state object key; defaults to `breakglass-observability/terraform.tfstate`.
- Variable `QUICKSIGHT_USER`: existing QuickSight username (the ARN is derived from the account and region).

Attach [permission-policy.json](permission-policy.json) to the assumed role. It grants Terraform access to the managed AWS services and the S3 state backend. The role also needs the GitHub OIDC trust policy described in the [troubleshooting guide](troubleshooting/README.md).

Pull requests run format, validation, and plan. Pushes to `master` or `main` apply the saved plan. Manual runs expose a `destroy` boolean: `false` applies the saved plan, while `true` runs `terraform destroy`. The assumed role must have the permissions required by the Terraform resources and the S3 backend.

## Troubleshooting

See the [troubleshooting guide](troubleshooting/README.md) for QuickSight setup, permissions, DNS, Firehose buffering size, and Firehose data-format conversion errors.

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

| Name                     | Type         | Default          | Description                                                     |
| ------------------------ | ------------ | ---------------- | --------------------------------------------------------------- |
| `aws_region`             | string       | `us-east-1`      | Deployment Region.                                              |
| `prefix`                 | string       | `breakglass`     | Resource-name prefix; account ID is appended to bucket names.   |
| `break_glass_role_name`  | string       | `BreakGlassRole` | Emergency role to create and detect.                            |
| `trusted_principal_arns` | list(string) | `[]`             | Principals allowed to assume it.                                |
| `log_retention_days`     | number       | `90`             | Parquet lifecycle expiration.                                   |
| `quicksight_user`        | string       | required         | Existing QuickSight username; its ARN is derived automatically. |
| `enable_glue_crawler`    | bool         | `true`           | Enable daily partition discovery.                               |

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

## Assume Role

```bash
aws sts assume-role \
        --role-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account | tr -d '"'):role/BreakGlassRole" \
        --role-session-name "bg-session"
```
