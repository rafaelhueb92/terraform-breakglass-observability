# Troubleshooting

## Lambda dependency or `pyarrow` errors

The converter no longer imports `pyarrow`. It emits newline-delimited JSON, and Firehose converts that JSON to Parquet using the managed Glue table schema. If an old Lambda version reports this error:

```text
Runtime.ImportModuleError: Unable to import module 'handler': No module named 'pyarrow'
```

Run the latest Terraform workflow to deploy the dependency-free function:

```bash
terraform apply
```

The old Lambda layer is removed from the Terraform configuration during that apply. No Docker build is needed.

## Firehose conversion failures

If Firehose reports data-format conversion errors, verify that the Glue database/table exists and that the Firehose role can read the table metadata (`glue:GetDatabase`, `glue:GetTable`, `glue:GetTableVersion`, and `glue:GetTableVersions`). The Glue table columns must match the JSON fields emitted by `handler.py`.

## QuickSight principal ARN is invalid

`quicksight_user` must be the username of an existing QuickSight user. It is not an account ID or a full ARN. Retrieve the username with:

```bash
aws quicksight list-users \
  --aws-account-id <account-id> \
  --namespace default \
  --region us-east-1 \
  --query 'UserList[*].[Email,UserName,Arn]' \
  --output table
```

Supply only the returned ARN as the variable value:

```bash
terraform apply -var='quicksight_user=<user-name>'
```

## QuickSight service role has not been created

If QuickSight reports `ACCESS_DENIED: The QuickSight service role required to access your AWS resources has not been created yet`, create it from the QuickSight console:

1. Open QuickSight in its home Region.
2. Select **Manage QuickSight** → **Security & permissions** → **Add or remove**.
3. Enable **Amazon Athena**.
4. Grant access to the Parquet bucket and Athena query-results bucket.
5. Select **Finish**, then **Update**, and rerun `terraform apply`.

This creates QuickSight's service role and authorizes it to use Athena and the selected S3 buckets.

## QuickSight dataset permissions are rejected

The QuickSight API requires specific complete permission sets. This project grants the author permission set, including `CreateIngestion` and `CancelIngestion`. Pull the current Terraform configuration and rerun `terraform apply` if the API reports `Resultant state of ResourcePermissions ... is not supported`.

## QuickSight API hostname cannot be resolved

An error like the following is a DNS or network issue on the computer running Terraform:

```text
lookup quicksight.us-east-1.amazonaws.com: no such host
```

Check the active network, DNS, VPN, and proxy configuration, then retry. If the error refers to the removed `aws_quicksight_account_subscription.poc` resource, it is stale state from an earlier configuration. Detach only that state record:

```bash
terraform state rm module.analytics.aws_quicksight_account_subscription.poc
```

This command does not delete the QuickSight account; it only stops Terraform from managing that obsolete resource.

## GitHub Actions cannot assume the AWS role

The workflow uses GitHub's OIDC token; it does not use long-lived AWS access keys. The IAM role must trust the `token.actions.githubusercontent.com` OIDC provider and restrict the `sub` claim to this repository and its deployment branch. For example, replace the placeholders below with the repository owner/name and branch:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:<owner>/<repository>:ref:refs/heads/main"
      }
    }
  }]
}
```

Store that role ARN in the repository secret `AWS_ROLE_TO_ASSUME`. The workflow also expects repository variables `AWS_REGION`, `TF_STATE_BUCKET`, and `QUICKSIGHT_USER`. The state bucket must exist before the workflow starts.
