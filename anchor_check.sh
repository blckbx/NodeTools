#!/bin/bash

#### GUIDE ###############################################
# download this script with wget LINKTOFILE
# assumes lncli is globally available: whereis lncli

#### Execute #############################################
# execute with bash anchor_check.sh
# To show only entries with sat/vb below N, execute with bash anchor_check.sh --limit N
# For Umbrelians ☂️, execute with bash anchor_check.sh umbrel
# To show only entries for a specific PUBKEY, execute with bash anchor_check.sh --peer PUBKEY

#### One off #############################################
# get a list of commitment fee for your peer list with this: 
# $ lncli listchannels| jq -r '.channels | sort_by(.fee_per_kw | tonumber)[] | "\(.fee_per_kw | tonumber * 4 / 1000) sat/vb for \(.peer_alias) (\(.remote_pubkey))"' 
# Generally a good advice to check the commitment type of your existing channels. With LND, you can get a list with
# $ lncli listchannels | grep commitment_type
# Caveat: For Umbrel ☂️, you need to have lncli as an alias: 
# $ echo "alias lncli=\"/home/umbrel/umbrel/scripts/app compose lightning exec lnd lncli\"" >> ~/.bash_aliases
# $ source ~/.bash_aliases

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

if [[ $# -eq 1 && $1 == "--umbrel" ]]; then
    # Set the anchor_list variable for umbrel
    anchor_list="/home/umbrel/umbrel/scripts/app compose lightning exec lnd lncli"
else
    # Set the anchor_list variable for any other system
    anchor_list="lncli"
fi

# Check if --peer option is provided
if [[ $1 == "--peer" ]]; then
    PEER=$2
    LIMIT=$3
    # Get nodeinfo for the specified pubkey
    PEER_INFO=$($anchor_list getnodeinfo --pub_key "$PEER")
else
    LIMIT=$2
fi

# Define the list of channels sorted by total fee_per_kw ascending
CHANNELS=$($anchor_list listchannels | jq '.channels | sort_by(.fee_per_kw | tonumber)')

# Loop through each channel and extract the pubkey and fee_per_kw values
while read -r line; do
    # Extract the fee_per_kw and remote_pubkey values
    FEE_PER_KW=$(echo "$line" | jq -r '.fee_per_kw')
    PUBKEY=$(echo "$line" | jq -r '.remote_pubkey')

    # Check if --peer is provided and skip if PUBKEY does not match
    if [[ -n "$PEER" && "$PEER" != "$PUBKEY" ]]; then
        continue
    fi

    # Check if the pubkey is valid and get the alias name
    ALIAS=$(echo "$line" | jq -r '.peer_alias')
    if [ -z "$ALIAS" ]; then
        # Use the pre-fetched info if available
        if [ -n "$PEER_INFO" ]; then
            ALIAS=$(echo "$PEER_INFO" | jq -r '.node.alias')
        else
            # Fetch alias from getnodeinfo if not available
            ALIAS=$($anchor_list getnodeinfo --pub_key "$PUBKEY" | jq -r '.node.alias')
            if [ -z "$ALIAS" ]; then
                echo "Invalid node pubkey: $PUBKEY"
                exit 1
            fi
        fi
    fi

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
done <<< "$(echo "$CHANNELS" | jq -c '.[]')"
