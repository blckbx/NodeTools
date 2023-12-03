#!/bin/bash
#check-torpeers.sh
#This script is checking your peer partners for Tor connections.
#If your node is connected to a peer partner via tor which offers also clearnet connection,
#it will try to switch to clearnet for better ping times.
#use it via cronjob
#09/2023 created by @m1ch43lv
#12/2023: Added alias output instead of pubkey, channel count,
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

clearnet_only_count=0
hybrid_node_count=0
tor_only_count=0

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

    for SOCKET in "${addresses[@]}"; do
        if [[ "$SOCKET" == *.onion* ]]; then
            continue
        else
            found_clearnet=true
            echo "Attempting to change to clearnet address $SOCKET for node https://amboss.space/node/$pubkey"
            for ((i = 1; i <= 5; i++)); do
                $_CMD_LNCLI disconnect "$pubkey"
                $_CMD_LNCLI connect "$pubkey@$SOCKET"
                sleep 5

                CURRENT_CONNECTION=$($_CMD_LNCLI listpeers | jq -r --arg pubkey "$pubkey" '.peers[] | select(.pub_key == $pubkey) | .address')
                if [[ "$CURRENT_CONNECTION" != *.onion* ]]; then
                    local success_msg="Successfully connected to clearnet address $CURRENT_CONNECTION for node https://amboss.space/node/$pubkey"
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

OIFS=$IFS
IFS=$'\n'
PEER_PARTNERS=$($_CMD_LNCLI listpeers | jq ".peers[]" -c)
HYBRID_ON_TOR=false
for PEER in $PEER_PARTNERS; do
    PEER_PUBKEY=$(echo "$PEER" | jq -r '.pub_key')
    PEER_IP=$(echo "$PEER" | jq -r '.address')
    NODE_INFO=$($_CMD_LNCLI getnodeinfo $PEER_PUBKEY)
    PEER_ALIAS=$(echo $NODE_INFO | jq -r '.node.alias')
    INTERNAL_ADDRESSES=($(echo $NODE_INFO | jq -r '.node.addresses[].addr'))

    echo -n "Connected with $PEER_ALIAS through $PEER_IP"
    num_addresses=${#INTERNAL_ADDRESSES[@]}
    onion_count=$(echo "${INTERNAL_ADDRESSES[@]}" | grep -c '.onion')

    if [[ $onion_count -gt 0 && $num_addresses -gt 1 ]]; then
        ((hybrid_node_count++))
        echo " - Hybrid"
    elif [[ $onion_count -gt 0 ]]; then
        ((tor_only_count ++))
        echo -n " - Tor only"
        # Check if the address is IPv4
        if echo "$PEER_IP" | grep -qP '^\d{1,3}(\.\d{1,3}){3}'; then
            ((tor_only_exit_clear++))
            echo -n " with clearnet exit"
        fi
        echo ""
    else
        ((clearnet_only_count++))
        echo " - Clearnet only"
    fi

    # Check if the node has both onion and clearnet addresses
    if [[ "$PEER_IP" == *.onion* && $num_addresses -gt 1 ]]; then
        HYBRID_ON_TOR=true
        # Attempt switch to clearnet for hybrid nodes
        if ! attempt_switch_to_clearnet "$PEER_PUBKEY" "${INTERNAL_ADDRESSES[@]}"; then
            # If not successful, attempt to switch to clearnet via mempool addresses
            IFS=','
            MEMPOOL_NODE_INFO=$(curl -s "https://mempool.space/api/v1/lightning/nodes/$PEER_PUBKEY")
            MEMPOOL_ADDRESSES=($(echo "$MEMPOOL_NODE_INFO" | jq -r '.sockets'))
            attempt_switch_to_clearnet "$PEER_PUBKEY" "${MEMPOOL_ADDRESSES[@]}"
        fi
    fi
done
IFS=$OIFS

# Get the list of public keys of inactive channels
inactive_channels_count=0
reconnected_inactive_channels_count=0
inactive_channels=$(lncli listchannels --inactive_only --public_only | jq -r '.channels[].remote_pubkey')
for PEER_PUBKEY in $inactive_channels; do
    NODE_INFO=$($_CMD_LNCLI getnodeinfo $PEER_PUBKEY)
    PEER_ALIAS=$(echo $NODE_INFO | jq -r '.node.alias')
    echo -n "Inactive channel with $PEER_ALIAS - Trying to recover by disconnecting: "
    lncli disconnect $PEER_PUBKEY >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        echo "Success"
        ((reconnected_inactive_channels_count++))
    else
        echo "Failed"
        ((inactive_channels_count++))
    fi
done

total_count=$(($hybrid_node_count + $clearnet_only_count + $tor_only_count))
count_msg="Inactive: $inactive_channels_count (reconnect success: $reconnected_inactive_channels_count) - Connected: $total_count - Hybrid: $hybrid_node_count - Clearnet-only: $clearnet_only_count - Tor-only: $tor_only_count (with clearnet exit: $tor_only_exit_clear)"
echo "$count_msg"
$nothingtodo_msg=""
if [ !$HYBRID_ON_TOR ]; then
    nothingtodo_msg="Nothing to do. All hybrid nodes on Clearnet."
    echo "$nothingtodo_msg"
fi
pushover "$count_msg $nothingtodo_msg"
