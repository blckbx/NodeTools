#!/bin/bash

#### GUIDE ###############################################
# download this script with wget LINKTOFILE
# assumes lncli is globally available: whereis lncli
# execute with bash anchor_check.sh
# For Umbrelians ☂️, execute with bash anchor_check.sh umbrel

#### One off #############################################
# get a list of commitment fee for your peer list with this: 
# $ lncli listchannels| jq -r '.channels | sort_by(.fee_per_kw | tonumber)[] | "\(.fee_per_kw | tonumber * 4 / 1000) sat/vb for \(.peer_alias) (\(.remote_pubkey))"' 
# Generally a good advice to check the commitment type of your existing channels. With LND, you can get a list with
# $ lncli listchannels | grep commitment_type
# Caveat: For Umbrel ☂️, you need to have lncli as an alias: 
# $ echo "alias lncli=\"/home/umbrel/umbrel/scripts/app compose lightning exec lnd lncli\"" >> ~/.bash_aliases
# $ source ~/.bash_aliases

if [[ $# -eq 1 && $1 == "umbrel" ]]; then
    # Set the anchor_list variable for umbrel
    anchor_list="/home/umbrel/umbrel/scripts/app compose lightning exec lnd lncli"
else
    # Set the anchor_list variable for any other system
    anchor_list="lncli"
fi

# Define the list of channels sorted by total fee_per_kw ascending
CHANNELS=$($anchor_list listchannels | jq '.channels | sort_by(.fee_per_kw | tonumber)')

# Loop through each channel and extract the pubkey and fee_per_kw values
while read -r line; do
    # Extract the fee_per_kw and remote_pubkey values
    FEE_PER_KW=$(echo "$line" | jq -r '.fee_per_kw')
    PUBKEY=$(echo "$line" | jq -r '.remote_pubkey')

    # Check if the pubkey is valid and get the alias name
    ALIAS=$($anchor_list getnodeinfo --pub_key "$PUBKEY" | jq -r '.node.alias')
    if [ -z "$ALIAS" ]; then
      echo "Invalid node pubkey: $PUBKEY"
      exit 1
    fi

    # Calculate the sat_vbyte value
    SAT_VBYTE=$((FEE_PER_KW * 4 / 1000))

    # Print the results
    echo "$SAT_VBYTE sat/vb for $ALIAS ($PUBKEY)"
done <<< "$(echo "$CHANNELS" | jq -c '.[]')"
