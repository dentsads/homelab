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
except FileNotFoundError:
    print("S3 list failed: aws CLI not found", file=sys.stderr)
    sys.exit(1)
except subprocess.CalledProcessError as e:
    print(f"S3 list failed: {e.stderr or e}", file=sys.stderr)
    sys.exit(1)

try:
    data = json.loads(r.stdout)
except json.JSONDecodeError as e:
    print(f"Failed to parse S3 response: {e}", file=sys.stderr)
    sys.exit(1)

if not data:
    print(f"No S3 backups found under s3://{BUCKET}/{PREFIX}", file=sys.stderr)
    sys.exit(1)

if not isinstance(data, list):
    print(f"Unexpected S3 response: {data!r}", file=sys.stderr)
    sys.exit(1)

volumes = {}
for item in data:
    key = item["Key"]
    rest = key[len(PREFIX):]
    m = re.match(r"^(.+)_\d{4}-\d{2}-\d{2}_\d{6}\.tar\.gz\.gpg$", rest)
    if not m:
        continue
    vol = m.group(1)
    if vol not in volumes or item["LastModified"] > volumes[vol]["LastModified"]:
        volumes[vol] = item

if not volumes:
    print(f"No matching S3 backups found under s3://{BUCKET}/{PREFIX}", file=sys.stderr)
    sys.exit(1)

downloads = []
for vol, item in volumes.items():
    key = item["Key"]
    local = os.path.join(DEST, f"{vol}.tar.gz.gpg")
    downloads.append((key, f"{local}.part", local))

for key, temp, _ in downloads:
    try:
        subprocess.run(
            ["aws", "s3", "cp", f"s3://{BUCKET}/{key}", temp],
            capture_output=True, text=True, check=True)
    except FileNotFoundError:
        print(f"Failed to download {key}: aws CLI not found", file=sys.stderr)
        for _, temp_path, _ in downloads:
            if os.path.exists(temp_path):
                os.remove(temp_path)
        sys.exit(1)
    except subprocess.CalledProcessError as e:
        print(f"Failed to download {key}: {e.stderr or e}", file=sys.stderr)
        for _, temp_path, _ in downloads:
            if os.path.exists(temp_path):
                os.remove(temp_path)
        sys.exit(1)

for key, temp, local in downloads:
    os.replace(temp, local)
    print(f"Downloaded s3://{BUCKET}/{key} -> {local}")
