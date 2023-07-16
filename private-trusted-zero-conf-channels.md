### How to create private trusted zero-conf channels between routing node and a personal wallet app (Blixt Wallet)

Overview
```
______________                                            ______________
|            |............................................|            |
|   Routing  |       private, trusted, 0conf channel      |   Blixt    |
|    Node    |............................................|   Wallet   |
|____________|                                            |____________|

[protocol]                                                ChannelAcceptor - Set zero conf peers:
protocol.option-scid-alias=true                           pubkey routing node
protocol.zero-conf=true
```

Activate Dev Screen on Blixt Wallet:
```
Settings -> Name
Set Name: Hampus
New Setting "Go to dev screen" appears
```

Connect Blixt Wallet to Routing Node:
```
Scroll down dev screen to "CONNECTPEER()" button.
Retrieve routing node infos on mobile phone via mempool.space and paste it into field above.
Connect
```

While connected, open private trusted zero conf channel:
```bash
bos open [pubkey] \
        --type private-trusted \
        --avoid-broadcast \
        --set-fee-rate 1 \
        --amount 10000000
        [--external-funding]
```

Close private trusted zero conf channel:
```bash
# Routing Node:
lncli abandonchannel ....

# Blixt Wallet:
TBD
```
