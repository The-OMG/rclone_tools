#!/usr/bin/env bash


## Contents of init.sh

cat_Help() {
  cat <<HELP
Usage: supertransfer [OPTION]

##############################
ATTN: Commands not ready yet!
##############################

-s, --status           bring up status menu (not ready)
-l, --logs             show program logs
-r, --restart          restart daemon
    --stop             stop daemon
    --start            start daemon

-c, --config           start configuration wizard
    --config-rclone    interactively configure gdrive service accounts
    --purge-rclone     remove all service accounts and reconfigure
    --set-email=EMAIL  config gdrive account impersonation
    --set-teamdrive=ID config teamdrive with ID (default: no)
    --set-path=PATH    config where files are stored on gdrive: (default: /)

    --pw=PASSWORD      unlocks secret multi-SA mode ;)
                       n00b deterrence:
                       password is reversed base64 of ZWxkcnVkCg==

-v  --validate         validates json account(s)
-V  --version          outputs version
-h, --help             what you're currently looking at

Please report any bugs to @flicker-rate#3637 on discord, or at plexguide.com
HELP
}

_configure_teamdrive_share() {
  source "$userSettings"
  [[ ! $(ls "$jsonPath" | grep -E .json$) ]] && log "configure_teamdrive_share : no jsons found" FAIL && exit 1
  [[ -z "$teamDrive" ]] && log "configure_teamdrive_share : no teamdrive found in config" FAIL && exit 1
  printf "$(grep \"client_email\" "${jsonPath}"/*.json | cut -f4 -d'"')\t" >/tmp/clientemails
  count=$(grep -c "@" /tmp/clientemails) # accurate count by @
  cat <<EOF
############ CONFIGURATION ################################
2) In your gdrive, share your teamdrive with
   the $count following emails:
      - tip: uncheck "notify people" & check "prevent editors..."
      - tip: ignore "sharing outside of org warning"
      - tip: Create a neew "group" in your admin console and add your
             service accont emails.
             Then share access to the "group" email.

###########################################################
EOF
  read -p 'Press Any Key To See The Emails'
  cat /tmp/clientemails
  echo
  echo 'NOTE: you can copy and paste the whole chunk at once'
  echo 'If you need to see them again, they are in /tmp/clientemails'
  read -p 'Press Any Key To Continue.'
  return 0
}

_CONFIG_Print_SA() {
  source "${userSettings}"
  #rclonePath=$(rclone -h | grep 'Config file. (default' | cut -f2 -d'"')
  rclonePath='/root/.config/rclone/rclone.conf'
  [[ -e ${rclonePath} ]] || mkdir -p ${rclonePath}
  [[ ! $(ls $jsonPath | egrep .json$) ]] && log "No Service Accounts Json Found." FAIL && exit 1
  # add rclone config for new keys if not already existing
  for json in ${jsonPath}/*.json; do
    if [[ ! $(egrep '^\[GDSA[0-9]+\]$' -A7 $rclonePath | grep $json) ]]; then
      oldMaxGdsa=$(egrep '^\[GDSA[0-9]+\]$' $rclonePath | sed 's/\[GDSA//g;s/\]//' | sort -g | tail -1)
      newMaxGdsa=$((++oldMaxGdsa))
      cat <<-CFG >>$rclonePath
[GDSA${newMaxGdsa}]
type = drive
client_id =
client_secret =
scope = drive
root_folder_id = $rootFolderId
service_account_file = $json
team_drive = $teamDrive

CFG
      ((++newGdsaCount))
    fi
  done
  [[ -n $newGdsaCount ]] && log "$newGdsaCount New Gdrive Service Account Added." INFO
  return 0
}

################################################################################
################################################################################
## Contents of rcloneupload.sh

#                      |---uploadQueueBuffer--|
#usage: rclone_upload  <dirsize> <upload_dir>  <rclone> <remote_root_dir>
rclone_upload() {
  local localFile="${2}"
  local sanitizedLocalFile
  sanitizedLocalFile=$(sed 's/(/\\(/g; s/)/\\)/g; s/\[/\\[/g; s/\]/\\]/g; s/\^/\\^/g; s/\*/\\*/g; s/"/\\"/g; s/!/\\!/g; s/+/\\+/g' <<<$localFile)
  # exit if file is locked, or race condtion met
  [[ $(egrep -x "${sanitizedLocalFile}" "$fileLock") ]] && return 1
  #[[ ! -d "${localFile}" ]] && return 1
  (cd "${localFile}" &>/dev/null) || return 1
  [[ -z $(ls "${localFile}" 2>/dev/null) ]] && return 1
  # lock file so multiple uploads don't happen
  echo "${localFile}" >>"$fileLock"
  local fileSize="${1}"
  local gdsa="${3}"
  local remoteDir="${4}"
  local rclone_fin_flag=0
  local driveChunkSize
  local rclone_fin_flag=0
  local t1=$(date +%s)

  # load latest usage value from db
  local oldUsage
  oldUsage=$(egrep -m1 ^$gdsa=. "$gdsaDB" | awk -F'=' '{print $2}')
  local Usage=$((oldUsage + fileSize))
  [[ -n $dbug ]] && echo -e " [DBUG]\t$gdsa\tUsage: $Usage"
  # update gdsaUsage file with latest usage value
  sed -i '/'^$gdsa'=/ s/=.*/='$Usage'/' $gdsaDB
  local gbFileSize
  gbFileSize=$(python3 -c "print(round($fileSize/1000000, 1), 'GB')")
  echo -e " [INFO] $gdsaLeast \tUploading: ${localFile#"$localDir"} @${gbFileSize}"
  [[ -n $dbug ]] && local gbUsage=$(python3 -c "print(round($Usage/1000000, 2), 'GB')")
  [[ -n $dbug ]] && -e " [DBUG] $gdsaLeast @${gbUsage}"

  # memory optimization
  local freeRam=$(free | grep Mem | awk '{print $4/1000000}')
  case $freeRam in
  [0123456789][0123456789][0123456789]*) driveChunkSize="1024M" ;;
  [0123456789][0123456789]*) driveChunkSize="1024M" ;;
  [6789]*) driveChunkSize="512M" ;;
  5*) driveChunkSize="256M" ;;
  4*) driveChunkSize="128M" ;;
  3*) driveChunkSize="64M" ;;
  2*) driveChunkSize="32M" ;;
  *) driveChunkSize="8M" ;;
  esac
  #echo "[DBUG] rcloneupload: localFile=${localFile}"
  #echo "[DBUG] rcloneupload: raw input 2=$2"

  local tmp=$(echo "${2}" | rev | cut -f1 -d'/' | rev | sed 's/ /_/g; s/\"//g')
  local logfile=${logDir}/${gdsa}_${tmp}.log

  local rcloneARGS=(
  "--tpslimit 6"
  "--checkers=20"
  "--config /root/.config/rclone/rclone.conf"
  "--transfers=8"
  "--log-file=${logfile}"
  "--log-level INFO"
  "--stats 5s"
  "--exclude="**partial~""
  "--exclude="**_HIDDEN~""
  "--exclude=".unionfs-fuse/**""
  "--exclude=".unionfs/**""
  "--drive-chunk-size=$driveChunkSize"
  )
  rclone move "${localFile}" "$gdsa:${localFile#"$localDir"}" \
  "${rcloneARGS[@]}" && rclone_fin_flag=1

  # check if rclone finished sucessfully
  local secs=$(($(date +%s) - $t1))
  if [[ $rclone_fin_flag == 1 ]]; then
    printf " [ OK ] $gdsaLeast\tFinished: "${localFile#"$localDir"}" in %dh:%dm:%ds\n" $(($secs / 3600)) $(($secs % 3600/60)) $(($secs % 60))
    sleep 10
    [[ -n $(ls "${localFile}") ]] && sleep 45 # sleep so files are deleted off disk before resuming; good for TV episodes
  else
    printf " [FAIL] $gdsaLeast\tUPLOAD FAILED: "${localFile}" in %dh:%dm:%ds\n" $(($secs / 3600)) $(($secs % 3600/60)) $(($secs % 60))
    cat "$logfile" >>/tmp/rclonefail.log
    [[ -n $dbug ]] && echo -e " [DBUG]\t$gdsa\tREVERTED Usage: $Usage"
    # revert gdsaDB back to old value if upload failed
    sed -i '/'^"$gdsa"'=/ s/=.*/='"$oldUsage"'/' "$gdsaDB"
  fi
  # release fileLock when file transfer finishes (or fails)
  egrep -xv "${sanitizedLocalFile}" "${fileLock}" >/tmp/fileLock.tmp && mv /tmp/fileLock.tmp "${fileLock}"
  [[ -e $logfile ]] && rm -f $logfile
}

################################################################################
################################################################################
## contents of config.sh

source /opt/plexguide/scripts/supertransfer/init.sh
source /opt/plexguide/scripts/supertransfer/rcloneupload.sh
source /opt/plexguide/scripts/supertransfer/settings.conf
source /opt/plexguide/scripts/supertransfer/spinner.sh

# Verify all prerequisite apps are installed and in path
declare -a reqlist=(rclone awk sed egrep grep echo printf find sort tee python3)
for app in $reqlist; do
  [[ ! $(which $app) ]] && echo -e "$app dependency not met/nPlease install $app" && exit 1
done

# source settings
[[ ! -d $jsonPath ]] && mkdir $jsonPath &>/dev/null
[[ ! -d $logDir ]] || mkdir $logDir &>/dev/null
[[ ! -e $userSettings ]] && cp /opt/plexguide/scripts/supertransfer/usersettings_template_dont_edit ${userSettings}
[[ ! -e ${jsonPath}/auto-rename-my-keys.sh ]] && cp /opt/plexguide/scripts/supertransfer/auto-rename-my-keys.sh $jsonPath
[[ ! -e $userSettings ]] && echo "Config at $userSettings Could Not Be Created."
source $userSettings

function _configure_teamdrive() {

source $userSettings
  if [[ -z $teamDrive ]]; then
      log "No Teamdrive Configured in: usersettings.conf" WARN
cat <<EOF

a) If you already have data in a personal drive, you can
   easily copy it over to the team drive.

 limitations: 1) Only 250,000 files allowed per teamdrive
              2) Folders may only be 20 directories deep

########## INSTRUCTIONS ###################################
1) Make a Team Drive in the Gdrive webui.
2) Find the Team Drive ID— [32mit looks like this:[0m
   https://drive.google.com/drive/folders/[32m084g3BHcoUu8IHgWUo5PSA[0m
###########################################################
EOF

      read -p 'Please Enter your Team Drive ID: ' teamId
      sed -i '/'^teamDrive'=/ s/=.*/='$teamId'/' $userSettings
      source $userSettings
      [[ $teamId == $teamDrive ]] && log "SA Accounts Configured to use team drives." INFO || log "Failed To Update Settings" FAIL
  fi
}

# configure json's for rclone
_CONFIG_Print_SA
gdsaList=$(rclone listremotes --config /root/.config/rclone/rclone.conf | sed 's/://' | egrep '^GDSA[0-9]+$')
[[ -z $gdsaList ]] && log "Rclone Configuration Failure." FAIL && exit 1

# validate new keys
function _validate_json(){
  echo '' > /tmp/SA_error.log
  for gdsa in $gdsaList; do
    s=0
    start_spinner "Validating: ${gdsa}"
    rclone touch ${gdsa}:${rootDir}/SA_validate &>/tmp/.SA_error.log.tmp && s=1
    if [[ $s == 1 ]]; then
      stop_spinner 0
    else
      cat /tmp/.SA_error.log.tmp >> /tmp/SA_error.log
      stop_spinner 1
      ((gdsaFail++))
    fi
  done

  # help user troubleshoot
  if [[ -n $gdsaFail ]]; then
    log "$gdsaFail Validation Failure(s). " WARN
    cat_Troubleshoot
  read -p "Continue anyway? y/n>" answer
  [[ ! $answer =~ [y|Y|Yes|yes] || ! $answer == '' ]] && exit 1
  fi

}
_SA_Key_Check
_configure_teamdrive
_configure_teamdrive_share
_validate_json

echo "[DBUG] config script end."
