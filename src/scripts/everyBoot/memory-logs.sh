#!/bin/bash

# mount /var/log on tmpfs to not wear down the eMMC flash chip
ISTMPFS=$(/bin/mount | /bin/grep -c "/var/log type tmpfs")

if [ "$ISTMPFS" == 0 ]; then
  mount -t tmpfs -o size=100M tmpfs /var/log

  #if we mount while the programs are still active and they keep their logfiles open, they keep on writing to the
  #(now hidden) location on the eMMC, so we need to restart or send the HUP signal (if it's properly impemented)
  mkdir /var/log/ntpstats /var/log/mgetty
  chown ntp:ntp /var/log/ntpstats/
  service ntp restart
  pkill -HUP valhalla_server
  initctl restart rsyslog

  ssh ic "mount -t tmpfs -o size=100M tmpfs /var/log"
  ssh ic "mkdir /var/log/ntpstats /var/log/mgetty"
  ssh ic "service ntp restart"
  ssh ic "initctl restart rsyslog"
fi
