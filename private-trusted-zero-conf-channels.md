### How to create private-trusted zero-conf channels between routing node and Blixt Wallet

Overview
```
______________                                            ______________
|            |............................................|            |
|   Routing  |       private, trusted, 0conf channel      |   Blixt    |
|    Node    |............................................|   Wallet   |
|____________|                                            |____________|
```

Routing Node requires some necessary options set in `lnd.conf`:
```ini
[protocol]
protocol.option-scid-alias=true
protocol.zero-conf=true
```

Start Blixt Wallet with Tor enabled
```
On first start, choose setting: Enable Tor
```

Allow routing node to open zero conf channels:
```
Settings -> Set zero conf peers
Enter routing node's pubkey (look up on mempool.space)
App requires restart
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
$ bos open [pubkey] \
        --type private-trusted \
        --avoid-broadcast \
        --set-fee-rate 1 \
        --amount 10000000
        [--external-funding]
```

Move balance to Blixt side (repeat on depletion of Blixt side):
```
On Blixt, create an invoice: lnbc1......
Pay the invoice from the routing node.
```

Disable Tor on Blixt Wallet:
```
Settings -> uncheck "Enable Tor"
Restart App
Check if lightning channel returns to state "active"
```

Close private trusted zero conf channel:
```bash
# Routing Node:
lncli abandonchannel ....

# Blixt Wallet:
TBD
```
