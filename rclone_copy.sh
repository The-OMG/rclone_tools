#!/usr/bin/env bash

#usage: create a bash script that will call this script from github.

REMOTE="$1"
GDRIVE_REMOTE="$2"
rcloneARGS=(
  "--transfers=8"
  "--checkers=16"
  "--low-level-retries=20"
  "--stats=10s"
  "--retries=20"
  "-vv"
  "--min-size=0"
  "--contimeout=60s"
  "--timeout=300s"
  "--retries=3"
  "--drive-chunk-size=256m"
  "--fast-list"
  "--checksum"
  "--drive-upload-cutoff=256m"
  "--low-level-retries=10"
)

rclone copy "$REMOTE" "$GDRIVE_REMOTE" "${rcloneARGS{@}}"