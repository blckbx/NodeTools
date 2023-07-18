### How to Create Private-Trusted Zero-Conf Channels between Routing Node and Blixt Wallet

Overview
```
______________                                            ______________
|            |............................................|            |
|   Routing  |       private-trusted, 0conf channel       |   Blixt    |
|    Node    |............................................|   Wallet   |
|____________|                                            |____________|
```

Requirements:
- your own routing node
- [LND](https://github.com/LightningNetwork/lnd) 0.15.1+ (zero-conf support)
- [Balance of Satoshis](https://github.com/alexbosworth/balanceofsatoshis) (latest)
- [Blixt Wallet](https://github.com/hsjoberg/blixt-wallet) (latest)

____________________________

Routing Node requires some necessary options set in `lnd.conf`:
```ini
[protocol]
protocol.option-scid-alias=true
protocol.zero-conf=true
```

In Blixt Wallet, allow routing node to open zero conf channels:
```
Settings -> Set zero conf peers
Enter routing node's pubkey (lookup on mempool.space)
```

Connect Blixt Wallet to Routing Node:
```
Settings -> Show Lightning Peers
Lookup routing node's connection string via mempool.space, enter and connect.
```

Reminder: bos locks utxos for about 10 mins! If you don't have enough funds on the node, fund externally.

While connected, open (e.g. 10M) private trusted zero conf channel (note: set-fee-rate has to be set although tx is never broadcasted):
```bash
$ bos open [pubkey] \
        --type private-trusted \
        --avoid-broadcast \
        --set-fee-rate 1 \
        --amount 10000000
        [--external-funding]
```

Move balance to Blixt side (repeat on depletion of Blixt side):
```
On Blixt, create an invoice: lnbc1....
Transfer to and pay the invoice from the routing node.
```

Close private trusted zero conf channel:
```bash
# Routing Node:
$ lncli abandonchannel ....

# Blixt Wallet:
TBD
```
