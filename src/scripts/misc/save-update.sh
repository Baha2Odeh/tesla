#!/bin/bash

# Hosts: ic, cid
# Modes: usb, internal, ssh, ftp

# Usage: bash save-update.sh HOST MODE &> output.log &

function die() {
  echo "ERROR: $1" >&2
  exit 1
}

bash ./get-versions.sh

[[ $# < 3 ]] && die "Must have arguments of bash save-update.sh ic|cid usb|internal|ssh|ftp offline|online"

HOST="$1"
MODE="$2"
DESIREDPART="$3"

me="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
case $(ps -o stat= -p $$) in
*+*) die "Run this script in the background dummy: bash $me $1 $2 $3 &> output.log &" ;;
*) echo "OK: Running in background" ;;
esac

function initializeVariables() {
  SSHSERVER="-p 22 tesla@yourserver.com"
  FTPSERVER="username:password@ftp.example.com:21/directory-goes-here"
}

function cleanFTPUsername() {
  # If FTP username has an @, replace with %40
  USERNAME=$(echo $FTPSERVER | cut -d: -f1)
  ENCODEDUSERNAME=${USERNAME/@/%40}
  FTPSERVER=${FTPSERVER/$USERNAME/$ENCODEDUSERNAME}
}

function validateIC() {
  # Quick fail safe to move from cid to ic
  if [ "$HOST" = ic ] && [ $(hostname) = cid ]; then
    die "Run this script from ic"
  fi
}

function getFirmwareInfo() {
  PARTITIONPREFIX=$([ "$HOST" = ic ] && echo "mmcblk3p" || echo "mmcblk0p")
  STATUS=$([ "$HOST" = ic ] && curl http://ic:21576/status || curl http://cid:20564/status)

  # Online size
  NEWSIZE=$(echo "$STATUS" | grep 'Online dot-model-s size:' | awk -F'size: ' '{print $2}' | awk '{print $1/64}')

  # Online version
  NEWVER=$(cat "/usr/tesla/UI/bin/version.txt" |  sed 's/\s.*$//' |  cut -d= -f2 | cut -d\- -f1  | sed 's/[^0-9.]*//g')


  # Ty kalud for finding offline part number
  ONLINEPART=$(cat /proc/self/mounts | grep "/usr" | grep ^/dev/$PARTITIONPREFIX[12] | cut -b14)
  if [ "$ONLINEPART" == "1" ]; then
    OFFLINEPART=2
  elif [ "$ONLINEPART" == "2" ]; then
    OFFLINEPART=1
  else
    die "Could not determine offline partition"
  fi

  [ "$DESIREDPART" == "offline" ] && DESIREDPARTCALCULATED=$OFFLINEPART
  [ "$DESIREDPART" == "online" ] && DESIREDPARTCALCULATED=$ONLINEPART

  if [ "$DESIREDPART" == "offline" ]; then
    # Offline size
    NEWSIZE=$(echo "$STATUS" | grep 'Offline dot-model-s size:' | awk -F'size: ' '{print $2}' | awk '{print $1/64}')

    # All this to get the offline version number
    OFFLINEMOUNTPOINT="/offline-usr"
    mkdir $OFFLINEMOUNTPOINT 2>/dev/null
    mount -o ro /dev/$PARTITIONPREFIX$OFFLINEPART $OFFLINEMOUNTPOINT
    if [ ! -e "$OFFLINEMOUNTPOINT/deploy/platform.ver" ]; then
      echo "Error mounting offline partition."
      umount $OFFLINEMOUNTPOINT 2>/dev/null
      exit 0
    fi

    NEWVER=$(cat "$OFFLINEMOUNTPOINT/tesla/UI/bin/version.txt" | cut -d= -f2 | cut -d\- -f1)
    umount $OFFLINEMOUNTPOINT
    rmdir $OFFLINEMOUNTPOINT
  fi
}

function saveAPE() {
  APELOCATION=""
  APELOCATIONONE="/home/cid-updater/ape-cache.ssq"
  APELOCATIONTWO="/home/cid-updater/ape.ssq"
  [ -f $APELOCATIONONE ] && APELOCATION=$APELOCATIONONE
  [ -f $APELOCATIONTWO ] && APELOCATION=$APELOCATIONTWO

  if [ -z "$APELOCATION" ]; then
    echo "Skipping transfer of APE, did not find ssq file"
    return
  fi

  echo "Found APE image at $APELOCATION"

  # Download gateway config in case it doesn't exist
  echo "Attempting to download gateway config..."
  [ -x "$(command -v get-gateway-config.sh)" ] && [ "$HOST" = cid ] && bash get-gateway-config.sh

  APE="ape0"
  MODEL=$(</var/etc/dashw)

  [ "$MODEL" == 2 ] && APE="ape2"
  [ "$MODEL" == 3 ] && APE="ape25"
  [[ "$MODEL" -ge 4 ]] && APE="ape3"

  if [ "$APE" == "ape0" ]; then
    echo "Found ape image but could not determine APE version from dashw: $MODEL"
    echo "Defaulting to .ape0 so we still save this file"
  fi

  if [ "$MODE" = internal ]; then
    cp $APELOCATION /tmp/$NEWVER.$APE
  elif [ "$MODE" = usb ]; then
    sudo mount -o rw,noexec,nodev,noatime,utf8 /dev/sda1 /disk/usb.*/
    cp $APELOCATION /disk/usb.*/$NEWVER.$APE
    sync
    umount /disk/usb.*/
  elif [ "$MODE" = ssh ]; then
    scp $APELOCATION $SSHSERVER:~/$NEWVER.$APE
  elif [ "$MODE" = ftp ]; then
    curl -T $APELOCATION ftp://$FTPSERVER/$NEWVER.$APE
  fi
}

function saveUpdate() {
  if [ "$MODE" = internal ]; then
    echo "Saving to /tmp/$NEWVER.image"
    dd if=/dev/$PARTITIONPREFIX$DESIREDPARTCALCULATED bs=64 of=/tmp/$NEWVER.image count=$NEWSIZE
  elif [ "$MODE" = usb ]; then
    echo "Saving to /$NEWVER.image on usb"
    sudo mount -o rw,noexec,nodev,noatime,utf8 /dev/sda1 /disk/usb.*/
    dd if=/dev/$PARTITIONPREFIX$DESIREDPARTCALCULATED bs=64 of=/disk/usb.*/$NEWVER.image count=$NEWSIZE
    sync
    umount /disk/usb.*/
  elif [ "$MODE" = ssh ]; then
    echo "Saving to /tmp/$NEWVER.image on remote server via SSH"
    dd if=/dev/$PARTITIONPREFIX$DESIREDPARTCALCULATED bs=64 count=$NEWSIZE | ssh $SSHSERVER "dd of=/tmp/$NEWVER.image"
  elif [ "$MODE" = ftp ]; then
    echo "Saving to ~/$NEWVER.image on remote server via FTP"
    dd if=/dev/$PARTITIONPREFIX$DESIREDPARTCALCULATED bs=64 count=$NEWSIZE | curl -T - ftp://$FTPSERVER/$NEWVER.image
  else
    die "MODE must be one of usb | internal | ssh | ftp"
  fi
}

function saveNavigon() {
  # @TODO: Add navigon image to arguments

  NAVPART=$(cat /proc/mounts | grep opt/nav | head -n1 | cut -d " " -f1)
  NAVMOUNT=$(cat /proc/mounts | grep opt/nav | head -n1 | awk '{print $2;}')
  NAVSIZE=$(echo "$STATUS" | grep 'Online map package size:' | awk -F'Online map package size: ' '{print $2}' | awk '{print $1/64}')
  NAVVERSION=$(cat $NAVMOUNT/VERSION | head -n1 | cut -d " " -f1)
  echo "Version $NAVVERSION is mounted at $NAVPART $NAVMOUNT ($NAVSIZE)"
  dd if=$NAVPART bs=64 count=$NAVSIZE of=/disk/usb.*/$NAVVERSION.image
  SSHSERVER=spam@xyz.com
  rsync -r -v --progress --partial --append-verify $NAVMOUNT/. $SSHSERVER:~/$NAVVERSION/.
}

function main() {
  initializeVariables
  cleanFTPUsername
  validateIC
  getFirmwareInfo
  saveUpdate
  saveAPE
}

main
