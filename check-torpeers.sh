#!/bin/bash
#check-torpeers.sh
#This script is checking your peer partners for Tor connections.
#If your node is connected to a peer partner via tor which offers also clearnet connection,
#it will try to switch to clearnet for better ping times.
#
#09/2023 created by @m1ch43lv
#12/03/23: Added alias output instead of pubkey, channel count statistic,
#          determination hybrid/clearnet/tor and
#          inactive channels with reconnect function
#12/15/23: Inactive channels: try dis- and reconnecting.
#          Order of switching attempt to Clearnet changed. First internal db,
#          second external db (mempool) in case of lagging gossip propagation.
#Thanks to @blckbx and @weasel3 for contributions, debugging and hosting#
#
#use it via cronjob every 3h.
#example usage bolt setup for admin userspace -change admin to lnd if you want to run it for lnd userspace
# 0 */3 * * * /bin/bash /home/admin/check-torpeers.sh >> /home/admin/check-torpeers.log 2>&1

#Fill personal Telegram information
source ./config.cfg
TOKEN="$TOKEN"
CHATID="$CHATID"

# define lncli command - (un)comment which applies
# bolt/blitz installation
[ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc"
[ -z "$_CMD_LNCLI" ] && _CMD_LNCLI=/usr/local/bin/lncli
# umbrel
# _CMD_LNCLI="/home/umbrel/umbrel/scripts/app compose lightning exec -T lnd lncli"

# define timeout of disconnecting and reconnecting to peers
timeout_sec=20

pushover() {
    msg=$(echo -e "✉️ check-torpeers\n$1")
    torify curl -s \
    -d parse_mode="HTML" \
    -d text="$msg" \
    -d chat_id="$CHATID" \
    https://api.telegram.org/bot$TOKEN/sendmessage > /dev/null 2>&1
}

function attempt_switch_to_clearnet() {
    local pubkey="$1"
    local addresses=("$2")
    # Allow to interrupt script during timeout
    trap "echo 'Script interrupted'; exit" SIGINT

    for socket in "${addresses[@]}"; do
        if [[ "$socket" == *.onion* ]]; then
            continue
        else
            old_address=$($_CMD_LNCLI listpeers | jq -r --arg pubkey "$pubkey" '.peers[] | select(.pub_key == $pubkey) | .address')
            echo "Retry #1"
            for ((i = 1; i <= 3; i++)); do
                echo "Disconnecting $pubkey"
                timeout $timeout_sec $_CMD_LNCLI disconnect "$pubkey"
                if [ $? -eq 124 ]; then
                    echo "Timeout occurred while trying to disconnect"
                fi
                echo "Connecting to $pubkey@$socket"
                timeout $timeout_sec $_CMD_LNCLI connect "$pubkey@$socket"
                if [ $? -eq 124 ]; then
                    echo "Timeout occurred while trying to connect"
                fi

                current_address=$($_CMD_LNCLI listpeers | jq -r --arg pubkey "$pubkey" '.peers[] | select(.pub_key == $pubkey) | .address')
                echo -n "Checking connection... new address returned from listpeers: "
                if [[ -z "$current_address" ]]; then
                    echo "<EMPTY>"
                else
                    echo "$current_address"
                fi
                if [[ -n "$current_address" && "$current_address" != *.onion* ]]; then
                    local success_msg="Successfully connected to $current_address for node https://amboss.space/node/$pubkey"
                    echo "$success_msg"
                    pushover "$success_msg"
                    return 0
                elif [[ -z "$current_address" && $i -lt 3 ]]; then
                    echo "Retry #$(($i + 1))"
                    sleep 2
                elif [[ $i -lt 3 ]]; then
                    echo "Retry #$(($i + 1))"
                    sleep 2
                fi
            done
            # In case of unsuccessful clearnet connection reconnect to Tor to avoid inactive channel state
            if [[ -z "$current_address" ]]; then
                echo "Restoring Tor connection to $old_address"
                timeout $timeout_sec $_CMD_LNCLI connect "$pubkey@$old_address"
                if [ $? -eq 124 ]; then
                    echo "Timeout occurred while trying to connect to $pubkey@$old_address"
                fi
            fi
        fi
    done

    return 1
}


# Main program

# Initialize variables
hybrid_on_tor=false
hybrid_count=0
clearnet_only_count=0
tor_only_count=0
tor_only_exit_clear_count=0
attempt_successful_count=0

# Check connection type for connected nodes
OIFS=$IFS
IFS=$'\n'
peer_partners=$($_CMD_LNCLI listpeers | jq ".peers[]" -c)
for peer in $peer_partners; do

    peer_pubkey=$(echo "$peer" | jq -r '.pub_key')
    peer_ip=$(echo "$peer" | jq -r '.address')
    node_info=$($_CMD_LNCLI getnodeinfo "$peer_pubkey")
    peer_alias=$(echo "$node_info" | jq -r '.node.alias')
    # In case of no internal gossip information
    if [ -z "$node_info" ]; then
        peer_alias=$peer_pubkey
        # Try to remove missing node
        echo "Disconnecting $peer_pubkey with no gossip information"
        $_CMD_LNCLI disconnect "$peer_pubkey"
    fi

    echo -n "Connected with $peer_alias through $peer_ip"

    internal_addresses=($(echo "$node_info" | jq -r '.node.addresses[].addr'))
    num_addresses=${#internal_addresses[@]}
    onion_address=$(echo "${internal_addresses[@]}" | grep -c '.onion')

    # Determine which kind of node - hybrid/clearnet only/tor only
    if [[ $onion_address -gt 0 && $num_addresses -gt 1 ]]; then
        ((hybrid_count++))
        echo " - Hybrid"
    elif [[ $onion_address -gt 0 ]]; then
        ((tor_only_count++))
        echo -n " - Tor only"
        # Check if the address is IPv4
        if echo "$peer_ip" | grep -qP '^\d{1,3}(\.\d{1,3}){3}'; then
            ((tor_only_exit_clear_count++))
            echo -n " with clearnet exit"
        fi
        echo ""
    else
        ((clearnet_only_count++))
        echo " - Clearnet only"
    fi

    # Check if peer partner is hybrid (must have both: onion and clearnet address)
    if [[ "$peer_ip" == *.onion* && $num_addresses -gt 1 ]]; then
        hybrid_on_tor=true
        echo "First switching attempt using internal clearnet address from gossip"

        if ! attempt_switch_to_clearnet "$peer_pubkey" "${internal_addresses[@]}"; then
            attempt_successful=false

            # In case of lagging gossip - Second attempt to switch to clearnet using mempool clearnet address
            IFS=','
            mempool_node_info=$(curl -s "https://mempool.space/api/v1/lightning/nodes/$peer_pubkey")
            mempool_addresses=($(echo "$mempool_node_info" | jq -r '.sockets'))
            IFS=$'\n'

            # Compare mempool_addresses with internal_addresses
            match_found=false
            for mempool_addr in "${mempool_addresses[@]}"; do
                for internal_addr in "${internal_addresses[@]}"; do
                    if [[ "$mempool_addr" == "$internal_addr" ]]; then
                        match_found=true
                        break 2 # Exit both loops
                    fi
                done
            done

            # If no match found, proceed to second switching attempt
            if [ "$match_found" = false ]; then
                echo "Second switching attempt using clearnet address from mempool"
                if attempt_switch_to_clearnet "$peer_pubkey" "${mempool_addresses[@]}"; then
                    ((attempt_successful_count++))
                    attempt_successful=true
                fi
            else
                echo "No second attempt - mempool address matches internal address of lnd: $mempool_addr"
            fi

            if ! $attempt_successful; then
                fail_msg="Failed to switch to clearnet after multiple attempts for hybrid node https://amboss.space/node/$peer_pubkey"
                echo "$fail_msg"
                # Gives you an error via TG when switching to clearnet is not possible - comment out for less TG verbosity
                pushover "$fail_msg"
            fi
        else
            ((attempt_successful_count++))
        fi
    fi
done
IFS=$OIFS

# Check for inactive channels
# Get the list of public keys of inactive channels and try reconnecting
inactive_count=0
reconnected_inactive_count=0
active_channels=$($_CMD_LNCLI listchannels --active_only --public_only | jq -r '.channels[].remote_pubkey' | wc -l)
inactive_channels=$($_CMD_LNCLI listchannels --inactive_only --public_only | jq -r '.channels[].remote_pubkey')
for peer_pubkey in $inactive_channels; do
    node_info=$($_CMD_LNCLI getnodeinfo "$peer_pubkey")
    peer_alias=$(echo "$node_info" | jq -r '.node.alias')
    internal_addresses=($(echo "$node_info" | jq -r '.node.addresses[].addr'))
    num_addresses=${#internal_addresses[@]}
    onion_address=$(echo "${internal_addresses[@]}" | grep -c '.onion')

    echo -n "Inactive channel with $peer_alias"

    # Determine which kind of node - hybrid/clearnet only/tor only
    if [[ $onion_address -gt 0 && $num_addresses -gt 1 ]]; then
        ((hybrid_count++))
        echo " - Hybrid"
    elif [[ $onion_address -gt 0 ]]; then
        ((tor_only_count++))
        echo -n " - Tor only"
        # Check if the address is IPv4
        if echo "$peer_ip" | grep -qP '^\d{1,3}(\.\d{1,3}){3}'; then
            ((tor_only_exit_clear_count++))
            echo -n " with clearnet exit"
        fi
        echo ""
    else
        ((clearnet_only_count++))
        echo " - Clearnet only"
    fi

    echo "Reconnecting using internal addresses from gossip"
    if ! attempt_switch_to_clearnet "$peer_pubkey" "${internal_addresses[@]}"; then
        echo "Reconnecting inactive channel failed"
        ((inactive_count++))
    else
        echo "Reconnecting inactive channel successful"
        ((reconnected_inactive_count++))
    fi
done

# Statistics
total_count=$(( hybrid_count + clearnet_only_count + tor_only_count ))
count_msg1="Connected nodes: $total_count"
echo "$count_msg1"
count_msg2="   Hybrid nodes: $hybrid_count, successfully switched to clearnet: $attempt_successful_count"
echo "$count_msg2"
count_msg3="   Clearnet only nodes: $clearnet_only_count"
echo "$count_msg3"
count_msg4="   Tor only nodes: $tor_only_count (Tor exit through clearnet: $tor_only_exit_clear_count)"
echo "$count_msg4"
count_msg5="Active channels: $active_channels"
echo "$count_msg5"
count_msg6="Inactive channels: $inactive_count, successfully reconnected: $reconnected_inactive_count"
echo "$count_msg6"
count_msg="$count_msg1\n$count_msg2\n$count_msg3\n$count_msg4\n$count_msg5\n$count_msg6\n"

# Checking for clearnet switching
noswitch_msg=""
if ! $hybrid_on_tor; then
    noswitch_msg="All hybrid nodes on Clearnet."
    echo "$noswitch_msg"
fi

# Reporting via Telegram
pushover "$count_msg$noswitch_msg"
