#!/bin/bash
#check-torpeers.sh
#This script is checking your peer partners for Tor connections.
#If your node is connected to a peer partner via tor which offers also clearnet connection,
#it will try to switch to clearnet for better ping times.
#use it via cronjob
#09/2023 created by @m1ch43lv
#12/2023: Added alias output instead of pubkey, channel count statistics,
#         determination hybrid/clearnet/tor and
#         inactive channels with reconnect function
#Many thanks to @blckbx and @weasel3 for hosting, debugging and contributions
#
#example usage bolt setup
# 0 */3 * * * /bin/bash /home/admin/check-torpeers.sh >> /home/admin/check-torpeers.log 2>&1

#Fill personal information
TOKEN="xxx"    # Telegram 
CHATID="xxx"   # Telegram 

# define lncli command - (un)comment which applies
# bolt/blitz installation
[ -f ~/.bashrc ] && source ~/.bashrc
[ -z "$_CMD_LNCLI" ] && _CMD_LNCLI=/usr/local/bin/lncli
# umbrel
# _CMD_LNCLI="/home/umbrel/umbrel/scripts/app compose lightning exec -T lnd lncli"

pushover() {
    msg=$(echo -e "✉️ check-torpeers\n$1")
    torify curl -s \
    -d parse_mode="HTML" \
    -d text="$msg" \
    -d chat_id="$CHATID" \
    https://api.telegram.org/bot$TOKEN/sendmessage > /dev/null 2>&1
}

function attempt_switch_to_clearnet() {
    local pubkey=$1
    local addresses=($2)
    local found_clearnet=false

    for socket in "${addresses[@]}"; do
        if [[ "$socket" == *.onion* ]]; then
            continue
        else
            found_clearnet=true
            echo "Attempting to change to clearnet address $socket for node https://amboss.space/node/$pubkey"
            for ((i = 1; i <= 5; i++)); do
                $_CMD_LNCLI disconnect "$pubkey" > /dev/null 2>&1
                $_CMD_LNCLI connect "$pubkey@$socket" > /dev/null 2>&1
                sleep 5

                current_connection=$($_CMD_LNCLI listpeers | jq -r --arg pubkey "$pubkey" '.peers[] | select(.pub_key == $pubkey) | .address')
                if [[ "$current_connection" != *.onion* ]]; then
                    local success_msg="Successfully connected to clearnet address $current_connection for node https://amboss.space/node/$pubkey"
                    echo "$success_msg"
                    pushover "$success_msg"
                    return 0
                else
                    sleep 5
                fi
            done
        fi
    done

    if $found_clearnet ; then
        local fail_msg="Failed to switch to clearnet after multiple attempts for node https://amboss.space/node/$pubkey"
        echo "$fail_msg"
        # Gives you an error via TG when switching to clearnet is not possible - comment out for less TG verbosity
        pushover "$fail_msg"
    else
        local no_clearnet_msg="No clearnet address found for node https://amboss.space/node/$pubkey"
        echo "$no_clearnet_msg"
        # uncomment for more TG verbosity
        #pushover "$no_clearnet_msg"
    fi
    return 1
}


# Main program

# Initialize variables
hybrid_on_tor=false
hybrid_count=0
clear_only_count=0
tor_only_count=0
tor_only_exit_clear_count=0
attempt_successful_count=0

# Get peer partners
OIFS=$IFS
IFS=$'\n'
peer_partners=$($_CMD_LNCLI listpeers | jq ".peers[]" -c)
for peer in $peer_partners; do
    peer_pubkey=$(echo "$peer" | jq -r '.pub_key')
    peer_ip=$(echo "$peer" | jq -r '.address')
    node_info=$($_CMD_LNCLI getnodeinfo $peer_pubkey)
    peer_alias=$(echo $node_info | jq -r '.node.alias')
    internal_addresses=($(echo $node_info | jq -r '.node.addresses[].addr'))

    echo -n "Connected with $peer_alias through $peer_ip"
    num_addresses=${#internal_addresses[@]}
    onion_address=$(echo "${internal_addresses[@]}" | grep -c '.onion')

    # Determin which kind of node - hybrid/clearnet only/tor only
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
        # Attempt to switch to clearnet
        if ! attempt_switch_to_clearnet "$peer_pubkey" "${internal_addresses[@]}"; then
            # If not successful, second attempt to switch to clearnet using mempool addresses
            IFS=','
            mempool_node_info=$(curl -s "https://mempool.space/api/v1/lightning/nodes/$peer_pubkey")
            mempool_addresses=($(echo "$mempool_node_info" | jq -r '.sockets'))
            if attempt_switch_to_clearnet "$peer_pubkey" "${mempool_addresses[@]}"; then
                ((attempt_successful_count++))
            fi
        else
            ((attempt_successful_count++))
        fi
    fi
done
IFS=$OIFS

# Get the list of public keys of inactive channels and try reconnecting by disconnecting
inactive_count=0
reconnected_inactive_count=0
inactive_channels=$(lncli listchannels --inactive_only --public_only | jq -r '.channels[].remote_pubkey')
for peer_pubkey in $inactive_channels; do
    node_info=$($_CMD_LNCLI getnodeinfo $peer_pubkey)
    peer_alias=$(echo $node_info | jq -r '.node.alias')
    echo -n "Inactive channel with $peer_alias - Trying to recover by disconnecting: "
    $_CMD_LNCLI disconnect $peer_pubkey >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        echo "Success"
        ((reconnected_inactive_count++))
    else
        echo "Failed"
        ((inactive_count++))
    fi
done

# Statistics
total_chan_count=$(($hybrid_count + $clearnet_only_count + $tor_only_count))
count_msg="Connected: $total_chan_count - Hybrid: $hybrid_count (successful switching to clearnet: $attempt_successful_count)\
 - Clearnet-only: $clearnet_only_count - Tor-only: $tor_only_count (exit through clearnet: $tor_only_exit_clear_count)\
 - Inactive: $inactive_count (successful reconnection: $reconnected_inactive_count)."
echo "$count_msg"

# Checking for clearnet switching
nothingtodo_msg=""
if ! $hybrid_on_tor; then
    nothingtodo_msg="Nothing to do, all hybrid nodes on Clearnet."
    echo "$nothingtodo_msg"
fi

# Reporting via Telegram
pushover "$count_msg\n$nothingtodo_msg"
