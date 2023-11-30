#!/bin/bash

# This script outputs the top 10 channels with the most updates. 
# Additionally, it provides the total sum of updates for all channels of the node.
#
# This script aids in pinpointing channels that can be closed/reopened when the overall
# HTLC processing time is sluggish, and the database size has outgrown the capacity 
# of the current hardware.
#
# While a sum of around 100 million updates is manageable on a Raspberry Pi (own measures), 
# multiples of this value might pose potential issues.
#
# made by @fry_aldebaran
#
# usage: bash checkChannelUpdates.sh
#
# version: 1.1
# date: 2023-11-30

# define lncli command - (un)comment which applies
# bolt/blitz installation
[ -f ~/.bashrc ] && source ~/.bashrc
[ -z "$_CMD_LNCLI" ] && _CMD_LNCLI=/usr/local/bin/lncli
# umbrel
# _CMD_LNCLI="/home/umbrel/umbrel/scripts/app compose lightning exec -T lnd lncli"

log_file="${0%.sh}.log"
echo "Logging output to ${log_file}" 
echo "See logfile for the 10 most updated channels"

# Empty the existing log file
truncate -s 0 "$log_file"
date >> "$log_file"
echo "Below are the 10 channels with the most updates" >> "$log_file"

# Initialize sum variable
total_updates=0

while read -r updates pubkey alias; do

    # alias check fallback
    [[ -z "$alias" ]] && alias=$($_CMD_LNCLI getnodeinfo --pub_key \"$pubkey\" | jq -r '.node.alias')
    if [ -z "$alias" ]; then
        echo "Invalid node pubkey: $pubkey"
        exit 1
    fi

    echo -e "$updates\t$pubkey\t$alias" >> "$log_file"

    # Update sum variable
    total_updates=$((total_updates + updates))

done < <($_CMD_LNCLI listchannels | jq -r '.channels[] | [.num_updates, .remote_pubkey, .peer_alias] | @tsv' | sort -rn | head -n 10)

# Output the total line
echo "Total updates of all channels: $total_updates" | tee -pa "$log_file"
