💻 Node Management Scripts & Best Practices

- [htlcScan.sh](/htlcScan.sh): scans through incoming and outgoing htlcs calculating expiration heights. informs the user via telegram if there're many (>10, configurable) pending htlcs. if htlcs are about to expire (< 13 blocks away), the script disconnects both parties up and down the route and thus trying to resolve the pending htlcs.
- [check-torpeers.sh](/check-torpeers.sh): scans through connected peers and tries to switch hybrid peers currently connected to Tor to their respective clearnet address.
- [bosLogRawTx.service](/bosLogRawTx.service): a simple background service logging every onchain transaction and its transaction hex made by the node to republish the hex at a later time, if necessary.
- [bosRules.service](/bosRules.service): a simple background service that enforces a rich set of rules to incoming channel requests. see description in service file what it's able to do.
- [private-trusted-zero-conf-channels](/private-trusted-zero-conf-channels.md): short overview on how to setup private-trusted zero-conf channels between a routing node (LND) and Blixt Wallet app (neutrino-backed LND mobile node w/ enabled zero-conf channel acceptor)
- [anchor_check.sh](/anchor_check.sh): This script shows all your channel peers anchor commit fee-rate in ascending order. Indicating high risk, once you identify a small commitment fee in high-mempool fee environment. Your force-close fee won't be enough and you'll run into a CPFP for your commitment tx to get into the next 2 blocks. Mitigation might be to lower traffic with high fees and minimize rebalancing.
- [checkChannelUpdates.sh](/checkChannelUpdates.sh): outputs the top 10 channels with the most updates. Additionally, it provides the total sum of updates for all channels of the node.

___________________________________
🏆 Credits to feelancer21, M1CH43LV, RocketNodeLN, ziggie1984, TrezorHannes, weasel3 et al.
