#!/bin/bash

# This script monitors various relevant system parameters and sends warnings 
# through a Telegram bot if specific thresholds are exceeded. 
# Resource-Checker monitors the usage of:
# - memory
# - swap memory
# - disk storage
# - long-term CPU usage (15-minute average)
# The user is notified via the Telegram bot when any of these 
# resources surpass predefined thresholds.
# It also monitors the sync-status of: 
# - the local bitcoin node's blockheight (against its peers and mempool.space)
# - the local lightning node's chain and graph
# The user is notified via the Telegram bot when the bitcoin node
# or the LN-chain/graph is out of sync
# With the flag -s only a SMART-report is pushed via the Telegram bot (sudo privileges necessary).
#
# made by @fry_aldebaran
#
# usage via crontab: */5 * * * * /bin/bash /home/admin/healthmonitor.sh
# or sudo crontab     0 20 * * * /bin/bash /home/admin/healthmonitor.sh --smartreport
#                    
# testing via terminal: /bin/bash /home/admin/healthmonitor.sh -t
#                       sudo /bin/bash /home/admin/healthmonitor.sh -s -t tg
#
# OPTIONS
# -t, --test [tg]
#        prints the output to terminal regardless of thresholds
#        the optional argument 'tg' forces the script to trigger the telegram-message pushover
#        which is in testmode on default disabled
# 
# -s, --smartreport
#        only runs the SMART-report function
#
# version: 2.4.0
# origin date: 2023-11-28
# mod date: 2025-02-28

# Initialize variables for flags
test_flag=false
test_tgpushover_flag=false
smartreport_flag=false
resourcecheck_flag=false

# Loop through all command line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -t|--test)
            test_flag=true
            if [ "$2" = "tg" ]; then 
              test_tgpushover_flag=true
              shift
            fi
            shift
            ;;
        -s|--smartreport)
            smartreport_flag=true
            # Check if the user has sudo privileges; exit if not
            if ! sudo -n true 2> /dev/null 2>&1; then
              echo "SMART-report can only run with sudo-privileges!"
              exit 1
            fi
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [-t|--test] [-s|--smartreport] [-h|--help]"
            exit 0
            ;;
        *)
            echo "Unknown parameter passed: $1"
            exit 1
            ;;
    esac
done

# toggle resourcecheck when no SMART-report is desired 
if [ ! "$smartreport_flag" = true ]; then 
  resourcecheck_flag=true
fi

# define btccli command
[ -f ~/.bashrc ] && source ~/.bashrc
[ -z "$_CMD_BTCCLI" ] && _CMD_BTCCLI=/usr/local/bin/bitcoin-cli
[ -z "$_CMD_LNCLI" ] && _CMD_LNCLI=/usr/local/bin/lncli

# setup telegram bot
# Check if the config file exists
script_path=$(dirname "$0")
if [ -f "$script_path/config.cfg" ]; then
    # Source the config file if it exists
    source $script_path/config.cfg
else
    # Use default values if the config file is missing
    echo "Warning: config.cfg not found. Using default values."
    TOKEN="YOUR_DEFAULT_TOKEN" 
    CHATID="YOUR_DEFAULT_CHATID" 
fi

# thresholds for Telegram-notification in percent
mem_threshold=90
swap_threshold=90
disk_threshold=90
cpu_threshold=95

# Limit of difference to the majority of your peers' blockheight to report
blkdiff_limit=1

# push message to TG bot
pushover() {
    msg=$(echo -e "ðŸš¨ healthmonitor\n$1")
    torify curl -s \
    -d parse_mode="HTML" \
    -d text="$msg" \
    -d chat_id="$CHATID" \
    https://api.telegram.org/bot$TOKEN/sendmessage > /dev/null 2>&1
}

# echo/pushover the message depending on test-flags
output() {
  if [ "$test_flag" = true ]; then 
    echo "$1"
    # With tgpushover-flag set, also report to Telegram
    if [ "$test_tgpushover_flag" = true ]; then
      pushover "$1"
    fi
  elif [ -n "$1" ]; then
    pushover "$1"
  fi
}

# Function to check resource usage and send warning if threshold exceeded
check_resource() {
    local value="$1"
    local threshold="$2"
    local message="$3"

    if (( $(awk -v value="$value" -v threshold="$threshold" 'BEGIN { if (value >= threshold) print 1; else print 0; }') )); then
        echo "WARNING: $message"
        pushover "WARNING: $message"
    fi

    # In Test-Mode printing to terminal regardless of threshold
    if [ "$test_flag" = true ]; then 
      local INFODATA=$(echo -e "INFO: $message \
                      \n(current value: $value, threshold: $threshold)")
      echo "$INFODATA"
      
      # With tgpushover-flag set, also report to Telegram
      if [ "$test_tgpushover_flag" = true ]; then
        pushover "$INFODATA"
      fi
    fi
}

if [ "$resourcecheck_flag" = true ]; then
  # Memory Usage
  mem_total=$(awk '/^MemTotal/ {print $2}' /proc/meminfo)
  mem_available=$(awk '/^MemAvailable/ {print $2}' /proc/meminfo)
  mem_usage=$((100 * (mem_total - mem_available) / mem_total))
  check_resource "$mem_usage" "$mem_threshold" "Memory is $mem_usage% saturated!"
  
  # Swap Memory Usage
  swap_total=$(awk '/^SwapTotal/ {print $2}' /proc/meminfo)
  swap_free=$(awk '/^SwapFree/ {print $2}' /proc/meminfo)
  if [ "$swap_free" -gt 0 ]; then
      swap_usage=$((100 * (swap_total - swap_free) / swap_total))
      check_resource "$swap_usage" "$swap_threshold" "Swap Memory is $swap_usage% saturated!"
  fi
  
  # Disk Usage
  disk_usage=$(df -h --output=pcent / | awk 'NR==2 {sub(/%/, ""); print}')
  check_resource "$disk_usage" "$disk_threshold" "Disk storage is $disk_usage% filled!"
  
  # Load Average (15min)
  cpu_count=$(nproc)
  load_average=$(top -bn1 | awk '/load average/ {print $(NF)}')
  cpu_usage=$(awk "BEGIN {printf \"%.2f\", 100 / $cpu_count * $load_average}")
  check_resource "$cpu_usage" "$cpu_threshold" "Load Average (15min) at $cpu_usage% ($load_average)!"
  
  # Blockheight compare to peers
  readarray -t peer_heights < <($_CMD_BTCCLI getpeerinfo | jq -r '.[] | .synced_blocks')
  readarray -t grouped_blkheights < <(echo "${peer_heights[@]}" | awk -v RS=' ' '{count[$1]++} END {for (height in count) print height, count[height]}' | sort -k2,2nr)
  #echo "grouped_blkheights:"
  #printf "%s\n" "${grouped_blkheights[@]}"
  majority_blkheight=${grouped_blkheights[0]%% *}
  local_blkheight=$($_CMD_BTCCLI getblockcount)

  mempoolSpaceHeight=$(curl -sSL "https://mempool.space/api/blocks/tip/height")
  if (( majority_blkheight - local_blkheight >= blkdiff_limit )); then
    BLKHEIGHT_MSG=$(echo -e "WARNING: Local blockheight ($local_blkheight) differs from most peers ($majority_blkheight)!\
                                \nFor reference mempool.space's blockheight: $mempoolSpaceHeight")
  elif [ "$test_flag" = true ]; then
    BLKHEIGHT_MSG=$(echo -e "INFO: Local blockheight ($local_blkheight) doesn't differ from most peers ($majority_blkheight).\
                                \nFor reference mempool.space's blockheight: $mempoolSpaceHeight")
  fi
  output "$BLKHEIGHT_MSG"
  
  # Check LN (Lightning Network) Sync Status
  ln_sync_info=$($_CMD_LNCLI getinfo)
  synced_to_chain=$(echo "$ln_sync_info" | jq -r '.synced_to_chain')
  synced_to_graph=$(echo "$ln_sync_info" | jq -r '.synced_to_graph')
  
  if [ "$synced_to_chain" != "true" ]; then
    CHAINSYNC_MSG="WARNING: LN not synced to chain!"
  elif [ "$test_flag" = true ]; then
    CHAINSYNC_MSG="INFO: LN synced to chain."
  fi
  output "$CHAINSYNC_MSG"
  
  if [ "$synced_to_graph" != "true" ]; then
    GRAPHSYNC_MSG="WARNING: LN not synced to graph!"
  elif [ "$test_flag" = true ]; then
    GRAPHSYNC_MSG="INFO: LN synced to graph."
  fi
  output "$GRAPHSYNC_MSG"
fi

if [ "$smartreport_flag" = true ]; then 
  # Weareout Alle physischen Laufwerke ermitteln (ohne Loop-Devices)
  DISKS=$(lsblk -dno NAME,TYPE | awk '$2 == "disk" {print $1}')
  # Schleife ueber alle ermittelten Laufwerke
  for DISK in $DISKS; do DEVICE="/dev/$DISK"
      # SMART-Info-Daten abrufen
      SMART_DATA=$(sudo smartctl -i $DEVICE 2>/dev/null)
      # Modellname extrahieren
      MODEL=$(echo "$SMART_DATA" | grep "Model Number" | awk -F': ' '{print $2}' | xargs)
      if [ -z "$MODEL" ]; then
        if [ "$test_flag" = true ]; then
          REPORT_DATA=$(echo "No SMART-Data for Device $DEVICE found.")
        fi
      else 
        # SMART-DATA fuer NVMe-SSDs extrahieren
        SMART_DATA=$(sudo smartctl -A $DEVICE 2>/dev/null | sed '1,3d')
        REPORT_DATA=$(echo -e "Daily SMART-Data-Report for $DEVICE\
                              \n$MODEL\n\
                              \n$SMART_DATA")
      fi
      
      output "$REPORT_DATA"
  done
fi
