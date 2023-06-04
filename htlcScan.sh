#!/bin/bash

# This script checks for pending stuck htlcs that are near expiration height (< 13 blocks).
# It collects peers of critical htlc and disconnects / reconnects them to reestablish the
# htlc. Sometimes htlcs are being resolved before expiration this way and thus costly
# force closes can be prevented.
#
# Credits to @feelancer21 & @M1ch43lV for putting this together
#
# usage: */30 * * * * /bin/bash /home/lnd/htlcScan.sh
#
# version: 1.0

# setup telegram bot
TOKEN="YOURBOTTOKEN"
CHATID="YOURCHATID"

# define lncli command
_CMD_LNCLI=lncli

# push message to TG bot
pushover() {
    msg=$(echo -e "✉️ htlcScan\n$1")
    torify curl -s \
    -d parse_mode="HTML" \
    -d text="$msg" \
    -d chat_id="$CHATID" \
    https://api.telegram.org/bot$TOKEN/sendmessage > /dev/null 2>&1
}


# disconnect and reconnect peers
function reconnect {
  local output=""

  output="Disconnecting:"
  ok=$(timeout 10 $_CMD_LNCLI disconnect $1 2>&1 | tr -d '[:space:]')
  [[ "$ok" == "{}" ]] && pushover "$output Success" || pushover "$output $ok"

  sleep 30

  local node_address=$(timeout 10 $_CMD_LNCLI getnodeinfo $1 | jq -r ".node.addresses[].addr" | grep -Po "([0-9]{1,3}[\.]){3}[0-9]{1,3}:[0-9]*" | head -n 1)
  output="Reconnecting after 30sec: "
  ok=$(timeout 10 $_CMD_LNCLI connect $1@$node_address 2>&1 | tr -d '[:space:]')
  if [ "$ok" == "{}" ]; then
    pushover "$output Success"
  else
    if echo "$ok" | grep -q "alreadyconnected"; then
      pushover "$output Already reconnected"
    else
      pushover "$output $ok"
      $_CMD_LNCLI getnodeinfo $1 | jq -r ".node.addresses[].addr" | grep -Po "([0-9]{1,3}[\.]){3}[0-9]{1,3}:[0-9]*" 1>/dev/null 2>&1
      local onion_address=$(timeout 10 $_CMD_LNCLI getnodeinfo $1 | jq -r ".node.addresses[].addr" | grep -P "onion" | head -n 1)
      output="Reconnecting to onion: "
      ok=$(timeout 10 $_CMD_LNCLI connect $1@$onion_address 2>&1 | tr -d '[:space:]')
      if [ "$ok" == "{}" ]; then
        pushover "$output Success"
      elif echo "$ok" | grep -q "alreadyconnected"; then
        pushover "$output Already reconnected"
      else
        pushover "$output $ok"
      fi
    fi
  fi
}

# calculate critical expiration height
blocks_til_expiry=13
current_block_height=$($_CMD_LNCLI getinfo | jq .block_height)
max_expiry=$((current_block_height + blocks_til_expiry))

# load channel list once
listchannels=$($_CMD_LNCLI listchannels)

# fetch pending htlcs
# check for outgoing and incoming
# reconnect predecessor and successor peer of critical htlcs
htlc_list=$(echo $listchannels | jq -r  ".channels[] | .pending_htlcs[] | select(.expiration_height < $max_expiry) | .hash_lock" | sort -u)
if [ -z "$htlc_list" ]; then
  echo "$(date "+%Y-%m-%d %H:%M:%S") no htlc(s) found with expiration < $blocks_til_expiry blocks"
  numhtlcs=$(echo $listchannels | jq -r  ".channels[] | .pending_htlcs[] | select(.expiration_height) | .hash_lock" | wc -l)
  [[ "$numhtlcs" -ne 0 ]] && pushover "No critical htlcs found.\n$numhtlcs pending htlc(s)"
  exit 0
fi

for hashlock in $htlc_list; do

    #check for outgoing htlcs
    pubkey=$(echo $listchannels | jq -r ".channels[] | select(.pending_htlcs[]? | select(.hash_lock==\"$hashlock\" and .incoming==false)) | .remote_pubkey")
    if [ ! -z "$pubkey" ]; then
      alias=$(echo $listchannels | jq -r ".channels[] | select(.remote_pubkey==\"$pubkey\" | .peer_alias")
      [[ -z "$alias" ]] && alias=$pubkey

      htlc_expiration_height=$(echo $listchannels | jq -r ".channels[] | .pending_htlcs[] | select(.hash_lock==\"$hashlock\" and .incoming==false) | .expiration_height")
      blocks_to_expire=$((htlc_expiration_height - current_block_height))
      pending_htlc_info="⚠ Outgoing htlc to $alias expires in $blocks_to_expire blocks."
      pushover "$pending_htlc_info"

      reconnect $pubkey
    fi

    #check for incoming htlcs
    pubkey=$(echo $listchannels | jq -r ".channels[] | select(.pending_htlcs[]? | select(.hash_lock==\"$hashlock\" and .incoming==true)) | .remote_pubkey")

    if [ ! -z "$pubkey" ]; then
      alias=$(echo $listchannels | jq -r ".channels[] | select(.remote_pubkey==\"$pubkey\" | .peer_alias")
      [[ -z "$alias" ]] && alias=$pubkey

      htlc_expiration_height=$(echo $listchannels | jq -r ".channels[] | .pending_htlcs[] | select(.hash_lock==\"$hashlock\" and .incoming==true) | .expiration_height")
      blocks_to_expire=$((htlc_expiration_height - current_block_height))
      pending_htlc_info="⚠ Incoming htlc to $alias expires in $blocks_to_expire blocks."
      pushover "$pending_htlc_info"

      reconnect $pubkey
    fi
done
