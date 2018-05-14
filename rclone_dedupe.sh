#!/usr/bin/env bash

# Usage: create a bash script that will call this script from github.
# Example: curl -s https://raw.githubusercontent.com/The-OMG/rclone_tools/master/rclone_copy.sh | bash /dev/stdin mygsuite:

REMOTE="$1"
LOGFILE="${HOME}/logs/$(date +"%d-%m-%Y_%H%M%S")-rclone_copy.log"
rcloneARGS=(
  "--checkers=8"
  "--contimeout=60s"
  "--dedupe-mode=newest"
  "--drive-chunk-size=64m"
  "--fast-list"
  "--log-file=$LOGFILE"
  "--log-level=error"
  "--low-level-retries=10"
  "--min-size=0"
  "--no-check-certificate"
  "--retries=20"
  "--retries=3"
  "--stats-log-level=ERROR"
  "--stats=10s"
  "--timeout=300s"
  "--transfers=8"
)

rclone dedupe "$REMOTE" "${rcloneARGS[@]}" &

echo "view your log file with:"
echo "tail -f $LOGFILE"
