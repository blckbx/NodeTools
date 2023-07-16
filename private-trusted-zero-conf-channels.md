### How to create private trusted zero-conf channels between routing node and a personal wallet app (Blixt Wallet)

```
______________                                            ______________
|            |____________________________________________|            |
|   Routing  |       private, trusted, 0conf channel      |   Blixt    |
|    Node    |____________________________________________|   Wallet   |
|____________|                                            |____________|

[protocol]                                                ChannelAcceptor - Set zero conf peers:
protocol.option-scid-alias=true                           pubkey routing node
protocol.zero-conf=true
```
Open private trusted zero conf channel:
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
