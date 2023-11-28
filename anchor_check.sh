#!/bin/bash

# Ask the user which LN system they are using
# Check if umbrel is provided as a command-line argument
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
