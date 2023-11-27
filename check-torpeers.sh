#!/bin/bash
#check-torpeers.sh
#This script is checking your peer partners for Tor connections. 
#If your node is connected to a peer partner via tor which offers also clearnet connection, 
#it will try to switch to clearnet for better ping times.
#use it via cronjob on a 6h basis
#09/2023 created by @m1ch43l_m2node

#example usage bolt setup
# 0 */6 * * * /bin/bash /home/lnd/check-torpeers.sh >> /home/lnd/check-torpeers.log 2&>1

#Fill personal information
TOKEN="xxx"    # Telegram 
CHATID="xxx"   # Telegram 
MY_NODE_PUBKEY="xxx"

# define lncli command - (un)comment which applies
# bolt/blitz installation
[ -f ~/.bashrc ] && source ~/.bashrc
[ -z "$_CMD_LNCLI" ] && _CMD_LNCLI=/usr/local/bin/lncli
# umbrel
# _CMD_LNCLI="/home/umbrel/umbrel/scripts/app compose lightning exec -T lnd lncli"

pushover() {
    torify curl -s \
    -d parse_mode="HTML" \
    -d text="$1" \
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
            for try in {1..5}; do
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
    
    if [[ $found_clearnet == true ]]; then
        local fail_msg="Failed to switch to clearnet after multiple attempts for node https://amboss.space/node/$pubkey"
        echo "$fail_msg"
        pushover "$fail_msg"
    else
        local no_clearnet_msg="No clearnet address found for node https://amboss.space/node/$pubkey"
        echo "$no_clearnet_msg"
        pushover "$no_clearnet_msg"
    fi
    return 1
}

OIFS=$IFS
IFS=$'\n'
PEER_PARTNERS=$($_CMD_LNCLI listpeers | jq ".peers[]" -c)
for PEER in $PEER_PARTNERS; do
    PEER_PUBKEY=$(echo "$PEER" | jq -r '.pub_key')
    PEER_IP=$(echo "$PEER" | jq -r '.address')
 
    echo "Connected with $PEER_PUBKEY through $PEER_IP"
    if [[ "$PEER_IP" == *.onion* && "$PEER_PUBKEY" != "$MY_NODE_PUBKEY" ]]; then
        IFS=','
        MEMPOOL_NODE_INFO=$(curl -s "https://mempool.space/api/v1/lightning/nodes/$PEER_PUBKEY")
        MEMPOOL_ADDRESSES=($(echo "$MEMPOOL_NODE_INFO" | jq -r '.sockets'))
 
        if ! attempt_switch_to_clearnet "$PEER_PUBKEY" "${MEMPOOL_ADDRESSES[@]}"; then
            IFS=$'\n'
            INTERNAL_ADDRESSES=($($_CMD_LNCLI getnodeinfo $PEER_PUBKEY | jq -r '.node.addresses[].addr'))
            attempt_switch_to_clearnet "$PEER_PUBKEY" "${INTERNAL_ADDRESSES[@]}"
        fi
    fi
done

IFS=$OIFS
