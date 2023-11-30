#!/bin/bash

# This script monitors system resource usage and sends warnings 
# through a Telegram bot if specific thresholds are exceeded. 
# It checks the usage of memory, swap memory, disk storage, 
# and long-term CPU usage (15-minute average). 
# The user is notified via the Telegram bot when any of these 
# resources surpass predefined thresholds.
# The script also uses bitcoin-cli to compare the local blockheight 
# with the majority of connected peers and mempool.space's and
# reports if it differs.
#
# made by @fry_aldebaran
#
# usage via crontab: */5 * * * * /bin/bash /home/admin/healthmonitor.sh
#
# version: 2.3.0
# origin date: 2023-11-28
# mod date: 2023-11-30

# define btccli command
[ -f ~/.bashrc ] && source ~/.bashrc
[ -z "$_CMD_BTCCLI" ] && _CMD_BTCCLI=/usr/local/bin/bitcoin-cli

# setup telegram bot
TOKEN="yourtoken"
CHATID="yourid"

# thresholds for Telegram-notification in percent
mem_threshold=90
swap_threshold=90
disk_threshold=90
cpu_threshold=95

# Limit of difference to the majority of your peers' blockheight to report
blkdiff_limit=1

# push message to TG bot
pushover() {
    msg=$(echo -e "🚨 healthmonitor\n$1")
    torify curl -s \
    -d parse_mode="HTML" \
    -d text="$msg" \
    -d chat_id="$CHATID" \
    https://api.telegram.org/bot$TOKEN/sendmessage > /dev/null 2>&1
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
}

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
echo "grouped_blkheights:"
printf "%s\n" "${grouped_blkheights[@]}"
majority_blkheight=${grouped_blkheights[0]%% *}
local_blkheight=$($_CMD_BTCCLI getblockcount)
echo "majority peers blockheight: $majority_blkheight"
echo "local blockheight: $local_blkheight"

if (( majority_blkheight - local_blkheight >= blkdiff_limit )); then
    mempoolSpaceHeight=$(curl -sSL "https://mempool.space/api/blocks/tip/height")
    pushover "WARNING: local blockheight ($local_blkheight) differs from most peers ($majority_blkheight)!\
    \nFor reference mempool.space's blockheight: $mempoolSpaceHeight"
fi
