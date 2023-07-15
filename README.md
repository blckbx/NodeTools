💻 Node Management Scripts

- [htlcScan.sh](/htlcScan.sh): scans through incoming and outgoing htlcs calculating expiration heights. informs the user via telegram if there're many (>10, configurable) pending htlcs. if htlcs are about to expire (< 13 blocks away), the script disconnects both parties up and down the route and thus trying to resolve the pending htlcs.
- [bosLogRawTx.service](/bosLogRawTx.service): a simple background service logging every onchain transaction and its transaction hex made by the node to republish the hex at a later time, if necessary.
- [bosRules.service](/bosRules.service): a simple background service that enforces a rich set of rules to incoming channel requests. see description in service file what it's able to do.

___________________________________
🏆 Credits to feelancer21, M1CH43LV, RocketNodeLN, ziggie1984 and the Blitz ⚡ Gang
