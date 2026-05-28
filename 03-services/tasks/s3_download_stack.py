#!/usr/bin/env python3
"""Download latest encrypted S3 backup per volume for a stack.

Reads from environment: S3_BUCKET, STACK_NAME, BACKUP_DIR,
plus AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION.
"""
import json, os, re, subprocess, sys

BUCKET = os.environ["S3_BUCKET"]
PREFIX = os.environ["STACK_NAME"] + "/"
DEST = os.path.normpath(os.path.join(os.environ["BACKUP_DIR"], os.environ["STACK_NAME"]))
os.makedirs(DEST, exist_ok=True)

try:
    r = subprocess.run(
        ["aws", "s3api", "list-objects-v2",
         "--bucket", BUCKET,
         "--prefix", PREFIX,
         "--query", "Contents[?ends_with(Key, '.tar.gz.gpg')]",
         "--output", "json"],
        capture_output=True, text=True, check=True)
    data = json.loads(r.stdout)
    if not isinstance(data, list):
        sys.exit(0)
except Exception as e:
    print(f"S3 list failed: {e}", file=sys.stderr)
    sys.exit(0)

if not data:
    sys.exit(0)

volumes = {}
for item in data:
    key = item["Key"]
    rest = key[len(PREFIX):]
    m = re.match(r"^(.+)_\d{4}-\d{2}-\d{2}_\d{6}\.tar\.gz\.gpg$", rest)
    if not m:
        continue
    vol = m.group(1)
    if vol not in volumes or item["LastModified"] > volumes[vol]["LastModified"]:
        volumes[vol] = key

for vol, key in volumes.items():
    local = os.path.join(DEST, f"{vol}.tar.gz.gpg")
    try:
        subprocess.run(
            ["aws", "s3", "cp", f"s3://{BUCKET}/{key}", local],
            check=True)
    except Exception as e:
        print(f"Failed to download {key}: {e}", file=sys.stderr)
