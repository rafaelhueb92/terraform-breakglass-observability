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

## Firehose `Lambda.InvokeAccessDenied`

If Firehose writes `processing-failed` objects to the `errors/` prefix with `errorCode: Lambda.InvokeAccessDenied`, the Firehose IAM role is missing permission to invoke the converter Lambda on the `$LATEST` qualifier.

Firehose invokes the Lambda using the qualified ARN `...converter:$LATEST`. The IAM policy must grant `lambda:InvokeFunction` on that qualified ARN, not just the unqualified function ARN. A policy that only lists the unqualified ARN is denied:

```text
Lambda.InvokeAccessDenied: Access was denied. Ensure that the access policy allows access to the Lambda function.
```

Verify with the IAM policy simulator, using the qualified ARN:

```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::<account-id>:role/<prefix>-firehose \
  --action-names lambda:InvokeFunction \
  --resource-arns 'arn:aws:lambda:<region>:<account-id>:function:<prefix>-converter:$LATEST'
```

The result must be `allowed`. If it is `implicitDeny`, add the qualified ARN to the `lambda:InvokeFunction` statement in `modules/ingestion/main.tf`:

```hcl
statement {
  actions   = ["lambda:InvokeFunction", "lambda:GetFunctionConfiguration"]
  resources = [aws_lambda_function.converter.arn, "${aws_lambda_function.converter.arn}:$LATEST"]
}
```

Then reapply:

```bash
terraform apply
```

The resource-based policy on the Lambda (`aws_lambda_permission.firehose`) is separate and does not need the qualifier; it already covers `$LATEST`. This error is distinct from the buffering-size tuning below.

## Firehose buffering size

The Firehose delivery stream is configured with `buffering_size = 64` MB. This was raised from the original 5 MB to reduce small Parquet fragments and improve Athena query performance. With a larger buffer, Firehose groups more records before landing each Parquet object, which lowers the number of objects scanned by Athena and reduces Glue crawler overhead.

If your pipeline produces low-volume traffic, you may see a corresponding increase in latency because records wait until the buffer is full or the `buffering_interval` (60 seconds) expires. This is expected. For high-volume pipelines, the larger buffer is more efficient.

To change the buffer size, edit `buffering_size` in `modules/ingestion/main.tf` and reapply:

```bash
terraform apply
```

Valid values are between 1 and 64 MB. Choose a smaller value if you need records delivered more quickly, or keep 64 MB for best query efficiency and cost at scale.

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
