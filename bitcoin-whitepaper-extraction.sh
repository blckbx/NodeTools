# Extract Bitcoin Whitepaper from Blockchain Data
# Full Node:
bitcoin-cli getrawtransaction 54e48e5f5c656b26c3bca14a8c95aa583d07ebe84dde3b7dd4a78f4e4186e713 true | jq -r '.vout[].scriptPubKey.asm' | \
cut -c3- | xxd -p -r | tail +9c | head -c 184292 > bitcoin.pdf

# Pruned Node:
seq 0 947 | (while read -r n; do bitcoin-cli gettxout 54e48e5f5c656b26c3bca14a8c95aa583d07ebe84dde3b7dd4a78f4e4186e713 $n | jq -r '.scriptPubKey.asm ' | \
awk '{ print $2 $3 $4 }'; done) | tr -d '\n' | cut -c 17-368600 | xxd -r -p > bitcoin-pruned.pdf
