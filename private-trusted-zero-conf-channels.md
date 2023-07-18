### How to Create Private-Trusted Zero-Conf Channels between Routing Node and Blixt Wallet

#### Overview
```
Node
     \
       \______________                                            ______________
Node __ |            |............................................|            |
        |   Routing  |       private-trusted, 0conf channel       |   Blixt    |
Node __ |    Node    |............................................|   Wallet   |
       /|____________|                                            |____________|
     /
Node
```

Requirements:
- your own routing node
- [LND](https://github.com/LightningNetwork/lnd) 0.15.1+ (zero-conf support)
- [Balance of Satoshis](https://github.com/alexbosworth/balanceofsatoshis) (latest)
- [Blixt Wallet](https://github.com/hsjoberg/blixt-wallet) (latest)

____________________________

#### Pros & Cons

| Pros | Cons |
|------|------|
| More secure: no remote access to routing node required | Experimental: Accounting of the node may get in trouble (fake overall balance, utxo locking) |
| No onchain costs: channel stays unconfirmed, no (force) closing costs due to internal management | Channel Management: Refilling of depleted Blixt side has to be done manually and directly on the node by paying an invoice. careful upfront planning of necessary liquidity has to be done |
| Non-custodial way of paying with Lightning | |
____________________________

#### Setup

Routing Node requires some necessary options set in `lnd.conf`:
```ini
[protocol]
protocol.option-scid-alias=true
protocol.zero-conf=true
```

In Blixt Wallet, allow your Routing Node to open zero-conf channels:
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

While connected, open (e.g. 10M) private-trusted zero-conf channel (note: `set-fee-rate` has to be set although tx is never broadcasted):
```bash
$ bos open [pubkey] \
        --type private-trusted \
        --avoid-broadcast \
        --set-fee-rate 1 \
        --amount 10000000
        [--external-funding]
```

Once established, move balance to Blixt side (repeat on depletion of Blixt side):
```
In Blixt, create an invoice: lnbc1....
Transfer to and pay the invoice from the routing node.
```

Close private-trusted zero-conf channel:
```bash
# Routing Node:
$ lncli abandonchannel ....

# Blixt Wallet:
TBD
```
