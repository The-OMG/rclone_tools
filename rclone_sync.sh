#!/usr/bin/env bash

# Usage: create a bash script that will call this script from github.
# Example: curl -s https://raw.githubusercontent.com/The-OMG/rclone_tools/master/rclone_copy.sh | bash /dev/stdin httpremote: mygsuite:
#

_Main() {
  local AvailableRam
  local GDRIVE_REMOTE="$2"
  local LOGFILE
  local REMOTE="$1"
  LOGFILE="${HOME}/logs/$(date +"%d-%m-%Y_%H%M%S")-rclone_copy.log"

  AvailableRam=$(free --giga -w | tee -a "$LOG_SCRIPT" | grep Mem | awk '{print $8}')
  case "$AvailableRam" in
  [1-9][0-9] | [1-9][0-9][0-9]) driveChunkSize="1024M" ;;
  [6-9]) driveChunkSize="512M" ;;
  5) driveChunkSize="256M" ;;
  4) driveChunkSize="128M" ;;
  3) driveChunkSize="64M" ;;
  2) driveChunkSize="32M" ;;
  [0-1]) driveChunkSize="8M" ;;
  esac

  rcloneARGS=(
    "--contimeout=60s"
    "--drive-chunk-size=$driveChunkSize"
    "--drive-upload-cutoff=$driveChunkSize"
    "--fast-list"
    "--log-level=DEBUG"
    "--low-level-retries=10"
    "--low-level-retries=20"
    "--min-size=0"
    "--no-check-certificate"
    "--retries=3"
    "--retries=20"
    "--stats-log-level=DEBUG"
    "--stats=10s"
    "--timeout=300s"
    "--tpslimit=6"
    "--track-renames"
    # "--checkers=8"
    # "--checksum"
    # "--log-file=$LOGFILE"
    # "--transfers=8"
  )

  rclone sync "$REMOTE" "$GDRIVE_REMOTE" "${rcloneARGS[@]}"

  echo "view your log file with:"
  echo "tail -f $LOGFILE"
}

_Main "$@"
