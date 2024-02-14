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
   --type string"$'\t\t'"filter by 'anchors' or 'static' output only
   --umbrel"$'\t\t'"adjust lncli since ☂ needs a different command call
   --btcpay"$'\t\t'"adjust lncli for BTCPay Server Docker environment
   -h, --help"$'\t\t'"Show this help message
"

# Check for --help option
if [[ $1 == "--help" || $1 == "-h" ]]; then
    echo "$help_text"
    exit 0
fi

# Set the anchor_list variable based on --umbrel or --btcpay option
if [[ $# -gt 0 && $1 == "--umbrel" ]]; then
    anchor_list="/home/umbrel/umbrel/scripts/app compose lightning exec -T lnd lncli"
elif [[ $# -gt 0 && $1 == "--btcpay" ]]; then
    anchor_list="docker exec btcpayserver_lnd_bitcoin lncli --macaroonpath /root/.lnd/admin.macaroon"
else
    anchor_list="/usr/local/bin/lncli"
fi

get_channel_info() {
    local CHANNEL_INFO=$1
    local line=$2
    ALIAS=$(echo "$CHANNEL_INFO" | jq -r '.peer_alias')
    FEE_PER_KW=$(echo "$CHANNEL_INFO" | jq -r '.fee_per_kw')
    ANCHOR=$(echo "$CHANNEL_INFO" | jq -r '.commitment_type')
    INITIATOR=$(echo "$CHANNEL_INFO" | jq -r '.initiator')
    if [[ "$ANCHOR" == "ANCHORS" ]]; then
        ANCHOR="⚓Anchors"
    elif [[ "$ANCHOR" == "STATIC_REMOTE_KEY" ]]; then
        ANCHOR="⚠  Static"
    else
        ANCHOR="🥪??"
    fi
}

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

    PUBKEY=$PEER
    get_channel_info "$CHANNEL_INFO" "$line"

    # Calculate the sat_vbyte value
    SAT_VBYTE=$((FEE_PER_KW * 4 / 1000))

    # Print SAT_VBYTE value
    echo "$INITIATOR $ANCHOR $SAT_VBYTE sat/vb "$'\t'" $ALIAS ($PUBKEY)"

else
    # Check if --type option is provided
    if [[ $1 == "--type" ]]; then
        if [[ $2 == "anchors" ]]; then
            TYPE="ANCHORS"
        elif [[ $2 == "static" ]]; then
            TYPE="STATIC_REMOTE_KEY"
        else
            echo "Invalid type: $2. Valid types are 'anchors' or 'static'."
            exit 1
        fi
        LIMIT=$3
    else
        # If --limit is provided, set the limit
        LIMIT=$2
    fi

    # Fetch and parse channel information
    CHANNELS=$($anchor_list listchannels | jq -c '.channels | sort_by(.fee_per_kw | tonumber)[]')

    # Loop through each channel and extract the pubkey and fee_per_kw values
    echo "Opener | Type | Commit "$'\t\t'" Alias "$'\t\t'" (Pubkey)"
    echo "$CHANNELS" | while read -r line; do
        # Extract the fee_per_kw, remote_pubkey, and peer_alias values.
	# Test to show initiator, too
        FEE_PER_KW=$(echo "$line" | jq -r '.fee_per_kw')
        PUBKEY=$(echo "$line" | jq -r '.remote_pubkey')
        ALIAS=$(echo "$line" | jq -r '.peer_alias')
        ANCHOR=$(echo "$line" | jq -r '.commitment_type')
	INITIATOR=$(echo "$line" | jq -r '.initiator')

        if [[ -n "$TYPE" && "$ANCHOR" != "$TYPE" ]]; then
            continue
        fi

        # Emoji setting for $line
        if [[ "$ANCHOR" == "ANCHORS" ]]; then
            ANCHOR_EMOJI="⚓Anchors"
        elif [[ "$ANCHOR" == "STATIC_REMOTE_KEY" ]]; then
            ANCHOR_EMOJI="⚠  Static"
        else
            ANCHOR_EMOJI="🥪"
        fi

        # Calculate the sat_vbyte value
        SAT_VBYTE=$((FEE_PER_KW * 4 / 1000))

        if [[ -z "$LIMIT" ]]; then
            # LIMIT is empty, print everything
            echo "$INITIATOR $ANCHOR_EMOJI $SAT_VBYTE sat/vb "$'\t'" $ALIAS ($PUBKEY)"
        else
            # LIMIT is not empty, proceed with filtering
            if [ "$SAT_VBYTE" -lt "$LIMIT" ]; then
                # Print everything below filter limit
                echo "$INITIATOR $ANCHOR_EMOJI $SAT_VBYTE sat/vb "$'\t'" $ALIAS ($PUBKEY)"
            else
                break
            fi
        fi
    done
fi
