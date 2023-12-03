#!/bin/bash

# Help text
help_text="
NAME:
   bash anchor_check.sh - Get information on your peer's fee-commitments

USAGE:
   bash anchor_check.sh [command options]

DESCRIPTION:
   shows all your channel peers anchor commit fee-rate in ascending order.

OPTIONS:
   --peer value"$'\t\t'"limit to only one specific pubkey
   --limit value"$'\t'"Show commitment-fee below specific limit
   --umbrel"$'\t\t'"adjust lncli since ☂️ needs a different command call
   -h, --help"$'\t\t'"Show this help message
"

# Check for --help option
if [[ $1 == "--help" || $1 == "-h" ]]; then
    echo "$help_text"
    exit 0
fi

# Set the anchor_list variable based on --umbrel option
if [[ $# -eq 1 && $1 == "--umbrel" ]]; then
    anchor_list="/home/umbrel/umbrel/scripts/app compose lightning exec lnd lncli"
else
    anchor_list="lncli"
fi

# Check if --peer option is provided
if [[ $1 == "--peer" ]]; then
    PEER=$2
    LIMIT=$3

    # Fetch channel information for the specified pubkey
    CHANNEL_INFO=$($anchor_list listchannels --peer "$PEER" | jq -r '.channels[0]')

    # Check if channel information is available
    if [ -z "$CHANNEL_INFO" ]; then
        echo "Invalid node pubkey or no channels found: $PEER"
        exit 1
    fi

    # Extract required information from the channel info
    ALIAS=$(echo "$CHANNEL_INFO" | jq -r '.peer_alias')
    FEE_PER_KW=$(echo "$CHANNEL_INFO" | jq -r '.fee_per_kw')
    PUBKEY=$PEER

    # Calculate the sat_vbyte value
    SAT_VBYTE=$((FEE_PER_KW * 4 / 1000))

    # Print SAT_VBYTE value
    echo "$SAT_VBYTE sat/vb for $ALIAS ($PUBKEY)"

else
    # If --limit is provided, set the limit
    LIMIT=$2

    # Fetch and parse channel information
    CHANNELS=$($anchor_list listchannels | jq -c '.channels | sort_by(.fee_per_kw | tonumber)[]')

    # Loop through each channel and extract the pubkey and fee_per_kw values
    echo "$CHANNELS" | while read -r line; do
        # Extract the fee_per_kw, remote_pubkey, and peer_alias values
        FEE_PER_KW=$(echo "$line" | jq -r '.fee_per_kw')
        PUBKEY=$(echo "$line" | jq -r '.remote_pubkey')
        ALIAS=$(echo "$line" | jq -r '.peer_alias')

        # Calculate the sat_vbyte value
        SAT_VBYTE=$((FEE_PER_KW * 4 / 1000))

        if [[ -z "$LIMIT" ]]; then
            # LIMIT is empty, print everything
            echo "$SAT_VBYTE sat/vb for $ALIAS ($PUBKEY)"
        else
            # LIMIT is not empty, proceed with filtering
            if [ "$SAT_VBYTE" -lt "$LIMIT" ]; then
                # Print everything below filter limit
                echo "$SAT_VBYTE sat/vb for $ALIAS ($PUBKEY)"
            else
                break
            fi
        fi
    done
fi
