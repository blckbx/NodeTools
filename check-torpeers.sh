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
#02/08/26: Optimized with parallel processing and IPv6 filtering.
#Thanks to @blckbx and @weasel3 for contributions, debugging and hosting#
#
#use it via cronjob every 3h.
#example usage bolt setup for admin userspace -change admin to lnd if you want to run it for lnd userspace
# 0 */3 * * * /bin/bash /home/admin/check-torpeers.sh >> /home/admin/check-torpeers.log 2>&1

# --- Configuration & Setup ---
script_path=$(dirname "$0")
if [ -f "$script_path/config.cfg" ]; then
    source "$script_path/config.cfg"
else
    echo "Warning: config.cfg not found. Using default values."
    TOKEN="YOUR_DEFAULT_TOKEN" 
    CHATID="YOUR_DEFAULT_CHATID" 
fi

[ -f "$HOME/.bashrc" ] && source "$HOME/.bashrc"
[ -z "$_CMD_LNCLI" ] && _CMD_LNCLI=/usr/local/bin/lncli

TIMEOUT_SEC=20
MAX_PARALLEL_JOBS=10
SEND_VERBOSE_MESSAGES=false
SKIP_IPV6=true # Default to true to prevent connection errors on IPv4/Tor nodes
DRY_RUN=${DRY_RUN:-false} # Set to true to skip actual connect/disconnect commands

# Temporary directory for job results
TMP_DIR=$(mktemp -d /tmp/check-torpeers.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

# --- Helper Functions ---

pushover() {
    local msg
    msg=$(echo -e "✉️ check-torpeers\n$1")
    torify curl -s \
    -d parse_mode="HTML" \
    -d text="$msg" \
    -d chat_id="$CHATID" \
    "https://api.telegram.org/bot$TOKEN/sendmessage" > /dev/null 2>&1
}

is_ipv6() {
    local addr="$1"
    # Matches patterns like [2a01:...] or 2a01:4ff:1f0:84c0::1 (multiple colons)
    if [[ "$addr" =~ \[.*\] ]] || [[ "$addr" =~ :.*: ]]; then
        return 0
    fi
    return 1
}

# --- Core Logic Functions ---

# Function to attempt switching to clearnet
# Arguments: pubkey, addresses (array string), old_address
attempt_switch_to_clearnet() {
    local pubkey="$1"
    local addresses=($2)
    local old_address="$3"

    for socket in "${addresses[@]}"; do
        [[ "$socket" == *.onion* ]] && continue
        if [ "$SKIP_IPV6" = true ] && is_ipv6 "$socket"; then
            echo "Skipping IPv6 address: $socket for $pubkey" >&2
            continue
        fi

        if [ "$DRY_RUN" = true ]; then
            echo "  [DRY_RUN] Would disconnect $pubkey and connect to $socket" >&2
            continue
        fi

        echo "Attempting connection to $pubkey @ $socket" >&2
        for ((i = 1; i <= 3; i++)); do
            echo "  Retry #$i: Re-connecting $pubkey to $socket" >&2
            timeout "$TIMEOUT_SEC" "$_CMD_LNCLI" disconnect "$pubkey" > /dev/null 2>&1
            timeout "$TIMEOUT_SEC" "$_CMD_LNCLI" connect "$pubkey@$socket" > /dev/null 2>&1
            
            # Check if successfully connected to clearnet
            local current_address
            current_address=$("$_CMD_LNCLI" listpeers | jq -r --arg pubkey "$pubkey" '.peers[] | select(.pub_key == $pubkey) | .address')
            
            if [[ -n "$current_address" && "$current_address" != *.onion* ]]; then
                local success_msg="Successfully connected to $current_address for node https://amboss.space/node/$pubkey"
                echo "$success_msg" >&2
                [ "$SEND_VERBOSE_MESSAGES" = true ] && pushover "$success_msg"
                return 0
            fi
            sleep 2
        done
        
        # Restore Tor if failed
        if [[ "$old_address" == *.onion* ]]; then
            echo "  Restoring Tor connection to $old_address" >&2
            timeout "$TIMEOUT_SEC" "$_CMD_LNCLI" connect "$pubkey@$old_address" > /dev/null 2>&1
        fi
    done
    return 1
}

# Process a single peer (intended for background execution)
process_peer() {
    local peer_json="$1"
    local job_id="$2"
    
    local pubkey
    pubkey=$(echo "$peer_json" | jq -r '.pub_key')
    local current_ip
    current_ip=$(echo "$peer_json" | jq -r '.address')
    
    local node_info
    node_info=$("$_CMD_LNCLI" getnodeinfo "$pubkey" 2>/dev/null)
    
    if [ -z "$node_info" ] || [ "$(echo "$node_info" | jq -r '.node // empty')" == "" ]; then
        echo "Disconnecting $pubkey with no gossip information" >&2
        "$_CMD_LNCLI" disconnect "$pubkey" > /dev/null 2>&1
        echo "RESULT:NONE:$pubkey:MISSING_GOSSIP" > "$TMP_DIR/job_$job_id"
        return
    fi
    
    local alias
    alias=$(echo "$node_info" | jq -r '.node.alias // $pubkey' --arg pubkey "$pubkey")
    local addresses
    addresses=($(echo "$node_info" | jq -r '.node.addresses[].addr' 2>/dev/null))
    
    local onion_count=0
    local clearnet_count=0
    for addr in "${addresses[@]}"; do
        if [[ "$addr" == *.onion* ]]; then
            ((onion_count++))
        else
            if [ "$SKIP_IPV6" = false ] || ! is_ipv6 "$addr"; then
                ((clearnet_count++))
            fi
        fi
    done
    
    local type="Tor only"
    if [[ $onion_count -gt 0 && $clearnet_count -gt 0 ]]; then
        type="Hybrid"
    elif [[ $onion_count -eq 0 ]]; then
        type="Clearnet only"
    fi
    
    local exit_clear=""
    if [[ "$type" == "Tor only" ]] && ! is_ipv6 "$current_ip" && [[ "$current_ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3} ]]; then
        exit_clear=" (Tor exit through clearnet)"
    fi
    
    echo "Connected with $alias through $current_ip - $type$exit_clear" >&2
    
    local switched=false
    if [[ "$type" == "Hybrid" && "$current_ip" == *.onion* ]]; then
        echo "Switching attempt for $alias ($pubkey)" >&2
        if attempt_switch_to_clearnet "$pubkey" "${addresses[*]}" "$current_ip"; then
            switched=true
        else
            # Second attempt via mempool
            local mempool_sockets
            mempool_sockets=$(curl -s "https://mempool.space/api/v1/lightning/nodes/$pubkey" | jq -r '.sockets[] // empty')
            if [[ -n "$mempool_sockets" ]]; then
                # Filter out already tried internal addresses
                local unique_mempool=()
                for m_addr in $mempool_sockets; do
                    local seen=false
                    for i_addr in "${addresses[@]}"; do
                        [[ "$m_addr" == "$i_addr" ]] && seen=true && break
                    done
                    [[ "$seen" == false ]] && unique_mempool+=("$m_addr")
                done
                
                if [ ${#unique_mempool[@]} -gt 0 ]; then
                    echo "Mempool attempt for $alias ($pubkey)" >&2
                    if attempt_switch_to_clearnet "$pubkey" "${unique_mempool[*]}" "$current_ip"; then
                        switched=true
                    fi
                fi
            fi
        fi
        
        if [ "$switched" = false ]; then
            pushover "Failed to switch to clearnet for hybrid node $alias (https://amboss.space/node/$pubkey)"
        fi
    fi
    
    echo "RESULT:PEER:$pubkey:$type:$switched:$exit_clear" > "$TMP_DIR/job_$job_id"
}

# Process inactive channel
process_inactive() {
    local pubkey="$1"
    local job_id="$2"
    
    local node_info
    node_info=$("$_CMD_LNCLI" getnodeinfo "$pubkey" 2>/dev/null)
    local alias
    alias=$(echo "$node_info" | jq -r '.node.alias // $pubkey' --arg pubkey "$pubkey")
    local addresses
    addresses=($(echo "$node_info" | jq -r '.node.addresses[].addr' 2>/dev/null))
    
    local onion_count=0
    local clearnet_count=0
    for addr in "${addresses[@]}"; do
        if [[ "$addr" == *.onion* ]]; then
            ((onion_count++))
        else
            if [ "$SKIP_IPV6" = false ] || ! is_ipv6 "$addr"; then
                ((clearnet_count++))
            fi
        fi
    done
    
    local type="Tor only"
    if [[ $onion_count -gt 0 && $clearnet_count -gt 0 ]]; then
        type="Hybrid"
    elif [[ $onion_count -eq 0 ]]; then
        type="Clearnet only"
    fi
    
    echo "Inactive channel with $alias - $type" >&2
    local reconnected=false
    if attempt_switch_to_clearnet "$pubkey" "${addresses[*]}" ""; then
        reconnected=true
    fi
    
    echo "RESULT:INACTIVE:$pubkey:$type:$reconnected" > "$TMP_DIR/job_inactive_$job_id"
}

# --- Main Program ---

main() {
    echo "Starting optimized check-torpeers..."

    # 1. Process Active Peers
    local job_id=0
    "$_CMD_LNCLI" listpeers | jq -c '.peers[]' | while read -r peer; do
        process_peer "$peer" "$job_id" &
        ((job_id++))
        
        while [[ $(jobs -r | wc -l) -ge $MAX_PARALLEL_JOBS ]]; do
            sleep 0.1
        done
    done
    wait

    # 2. Process Inactive Channels
    local active_channels
    active_channels=$("$_CMD_LNCLI" listchannels --active_only --public_only | jq -r '.channels[].remote_pubkey' | wc -l)
    "$_CMD_LNCLI" listchannels --inactive_only --public_only | jq -r '.channels[].remote_pubkey' | while read -r pubkey; do
        [[ -z "$pubkey" ]] && continue
        process_inactive "$pubkey" "$job_id" &
        ((job_id++))
        
        while [[ $(jobs -r | wc -l) -ge $MAX_PARALLEL_JOBS ]]; do
            sleep 0.1
        done
    done
    wait

    # 3. Aggregate Statistics
    local hybrid_count=0
    local clearnet_only_count=0
    local tor_only_count=0
    local tor_only_exit_clear_count=0
    local attempt_successful_count=0
    local inactive_count=0
    local reconnected_inactive_count=0

    for f in "$TMP_DIR"/job_*; do
        [[ -e "$f" ]] || continue
        IFS=':' read -r tag rtype pubkey ntype success extra <<< "$(cat "$f")"
        
        case "$ntype" in
            "Hybrid") ((hybrid_count++)) ;;
            "Clearnet only") ((clearnet_only_count++)) ;;
            "Tor only") 
                ((tor_only_count++))
                [[ -n "$extra" ]] && ((tor_only_exit_clear_count++))
                ;;
        esac
        
        if [[ "$rtype" == "PEER" && "$success" == "true" ]]; then
            ((attempt_successful_count++))
        elif [[ "$rtype" == "INACTIVE" ]]; then
            if [[ "$success" == "true" ]]; then
                ((reconnected_inactive_count++))
            else
                ((inactive_count++))
            fi
        fi
    done

    local total_count=$(( hybrid_count + clearnet_only_count + tor_only_count ))
    local count_msg1="Connected nodes: $total_count"
    local count_msg2="   Hybrid nodes: $hybrid_count, successfully switched to clearnet: $attempt_successful_count"
    local count_msg3="   Clearnet only nodes: $clearnet_only_count"
    local count_msg4="   Tor only nodes: $tor_only_count (Tor exit through clearnet: $tor_only_exit_clear_count)"
    local count_msg5="Active channels: $active_channels"
    local count_msg6="Inactive channels: $inactive_count, successfully reconnected: $reconnected_inactive_count"

    echo "$count_msg1"
    echo "$count_msg2"
    echo "$count_msg3"
    echo "$count_msg4"
    echo "$count_msg5"
    echo "$count_msg6"

    if [ "$SEND_VERBOSE_MESSAGES" = true ]; then
        pushover "$count_msg1\n$count_msg2\n$count_msg3\n$count_msg4\n$count_msg5\n$count_msg6"
    fi

    echo "Done."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
