#!/bin/bash

# This script monitors system resource usage and sends warnings 
# through a Telegram bot if specific thresholds are exceeded. 
# It checks the usage of memory, swap memory, disk storage, 
# and long-term CPU usage (15-minute average). 
# The user is notified via the Telegram bot when any of these 
# resources surpass predefined thresholds.
#
# made by @fry_aldebaran
#
# usage via crontab: */5 * * * * /bin/bash /home/admin/healthmonitor.sh
#
# version: 1.0
# date: 2023-11-28

# setup telegram bot
TOKEN="yourtoken"
CHATID="yourid"

# thresholds for Telegram-notification in percent
mem_threshold=90
swap_threshold=90
disk_threshold=90
cpu_threshold=95


# push message to TG bot
pushover() {
    msg=$(echo -e "   ^=^z    healthmonitor\n$1")
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
        pushover "WARNING: $message"
    fi
}

# Memory Usage
mem_usage=$(free | awk '/Mem/ {printf "%.2f\n", $3/$2 * 100}')
check_resource "$mem_usage" "$mem_threshold" "Memory is $mem_usage% saturated!"

# Swap Memory Usage
swap_usage=$(free | awk '/Swap/ {printf "%.2f\n", $3/$2 * 100}')
check_resource "$swap_usage" "$swap_threshold" "Swap Memory is $swap_usage% saturated!"

# Disk Usage
disk_usage=$(df -h --output=pcent / | awk 'NR==2 {sub(/%/, ""); print}')
check_resource "$disk_usage" "$disk_threshold" "Disk storage is $disk_usage% filled!"

# Load Average (15min)
cpu_count=$(nproc)
load_average=$(top -bn1 | awk '/load average/ {print $(NF)}')
cpu_usage=$(awk "BEGIN {printf \"%.2f\", 100 / $cpu_count * $load_average}")
check_resource "$cpu_usage" "$cpu_threshold" "Load Average (15min) at $cpu_usage% ($load_average)!"