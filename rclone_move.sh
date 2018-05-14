#!/usr/bin/env bash

# Usage: create a bash script that will call this script from github.
# Example: curl -s https://raw.githubusercontent.com/The-OMG/rclone_tools/master/rclone_copy.sh | bash /dev/stdin httpremote: mygsuite:

REMOTE="$1"
GDRIVE_REMOTE="$2"
LOGFILE="${HOME}/logs/$(date +"%d-%m-%Y_%H%M%S")-rclone_copy.log"
rcloneARGS=(
  "--transfers=8"
  "--checkers=8"
  "--low-level-retries=20"
  "--stats=10s"
  "--retries=20"
  "--min-size=0"
  "--contimeout=60s"
  "--timeout=300s"
  "--retries=3"
  "--drive-chunk-size=64m"
  "--fast-list"
  "--checksum"
  "--drive-upload-cutoff=64m"
  "--low-level-retries=10"
  "--stats-log-level=ERROR"
  "--no-check-certificate"
)

rclone move "$REMOTE" "$GDRIVE_REMOTE" "${rcloneARGS[@]}" | tee -a "$LOGFILE"
