# Extract Bitcoin Whitepaper from Blockchain Data
# Full Node:
```bash
$ bitcoin-cli getrawtransaction 54e48e5f5c656b26c3bca14a8c95aa583d07ebe84dde3b7dd4a78f4e4186e713  | sed 's/0100000000000000/\n/g' | \
tail -n +2 | cut -c7-136,139-268,271-400 | tr -d '\n' | cut -c17-368600 | xxd -p -r > bitcoin.pdf
```
# Pruned Node:
```bash
seq 0 947 | (while read -r n; do bitcoin-cli gettxout 54e48e5f5c656b26c3bca14a8c95aa583d07ebe84dde3b7dd4a78f4e4186e713 $n | jq -r '.scriptPubKey.asm ' | \
awk '{ print $2 $3 $4 }'; done) | tr -d '\n' | cut -c 17-368600 | xxd -r -p > bitcoin-pruned.pdf
```
