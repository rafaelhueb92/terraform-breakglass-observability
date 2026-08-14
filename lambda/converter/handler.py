"""Normalize only break-glass CloudTrail activity for Firehose delivery.

The Lambda emits newline-delimited JSON. Kinesis Firehose performs the Parquet
conversion using its native data-format conversion and the Glue table schema.
"""
import base64
import boto3
import gzip
import json
import os
from urllib.parse import unquote_plus


def is_breakglass(event):
    identity = event.get("userIdentity", {})
    issuer = identity.get("sessionContext", {}).get("sessionIssuer", {})
    issuer_arn = issuer.get("arn", "")
    # Role sessions reliably expose the issuer ARN; tags provide a second signal.
    tags = identity.get("sessionContext", {}).get("sessionTags", [])
    tagged = any(t.get("key") == "PROFILE" and t.get("value") == "BREAKING-GLASS" for t in tags)
    return "BreakGlassRole" in issuer_arn or tagged


def as_row(event):
    identity = event.get("userIdentity", {})
    issuer = identity.get("sessionContext", {}).get("sessionIssuer", {})
    return {
        "eventtime": str(event.get("eventTime", "")),
        "eventname": str(event.get("eventName", "")),
        "eventsource": str(event.get("eventSource", "")),
        "username": str(identity.get("userName") or issuer.get("userName") or ""),
        "sessionarn": str(identity.get("arn", "")),
        "sourceipaddress": str(event.get("sourceIPAddress", "")),
        "requestparameters": json.dumps(event.get("requestParameters"), default=str),
        "errorcode": str(event.get("errorCode", "")),
    }


def row_bytes(event):
    # Firehose's OpenX JSON deserializer consumes one JSON object per line.
    return (json.dumps(as_row(event), separators=(",", ":")) + "\n").encode()


def forward_cloudtrail_object(event):
    s3 = boto3.client("s3")
    firehose = boto3.client("firehose")
    key = unquote_plus(event["detail"]["object"]["key"])
    bucket = event["detail"]["bucket"]["name"]
    raw = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
    document = json.loads(gzip.decompress(raw))
    records = [{"Data": json.dumps(x).encode()} for x in document.get("Records", [])]
    for start in range(0, len(records), 500):
        firehose.put_record_batch(DeliveryStreamName=os.environ["FIREHOSE_STREAM"], Records=records[start:start + 500])


def lambda_handler(event, _context):
    # EventBridge performs the only supported S3-to-Firehose routing path.
    if event.get("source") == "aws.s3":
        forward_cloudtrail_object(event)
        return {"statusCode": 200}

    output = []
    for record in event.get("records", []):
        try:
            cloudtrail_event = json.loads(base64.b64decode(record["data"]))
            if not is_breakglass(cloudtrail_event):
                output.append({"recordId": record["recordId"], "result": "Dropped", "data": record["data"]})
            else:
                encoded = base64.b64encode(row_bytes(cloudtrail_event)).decode()
                output.append({"recordId": record["recordId"], "result": "Ok", "data": encoded})
        except (ValueError, KeyError, json.JSONDecodeError) as exc:
            # Preserve Firehose retry semantics for malformed input rather than silently losing it.
            output.append({"recordId": record.get("recordId", "unknown"), "result": "ProcessingFailed", "data": record.get("data", "")})
    return {"records": output}
