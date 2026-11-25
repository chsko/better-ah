# Forever uses the C_AuctionHouse API only

`/bah selftest` in the Forever client (interface 16001, build 1.60.1.71091, EU, Horde; output on #3) found none of the legacy browse functions (`QueryAuctionItems`, `GetAuctionItemInfo` and friends) and every `C_AuctionHouse` function we probed, including `SendBrowseQuery` and `ReplicateItems`. So the Auction API adapter is written against `C_AuctionHouse` only, with no legacy fallback. The interface number 16001 in the toc is confirmed.

A full scan with `ReplicateItems` works on Forever (2026-11-25, output on #5; EU, game mode 1, Horde, Undercity): 217,382 listings of 6,922 items, 20 seconds from the call to the `REPLICATE_ITEM_LIST_UPDATE` reply, with 83,846 listings (39%) without full item info. An earlier attempt got no reply within 120 seconds, for an unknown reason; a throttle like retail's 15-minute cooldown is one possibility. A polling fallback and a timeout report of what the client did were added after that run and are not verified in game yet.

Of the ruleset candidates, only `C_GameRules` answered: `GetActiveGameMode()` returned 1 and `IsHardcoreActive()` returned false. `C_Seasons` and `C_Realm.GetCurrentRulesetID` do not exist. One value from one ruleset doesn't show that `GetActiveGameMode` tells rulesets apart; that needs a run on a second ruleset.

## Open, carried to #5

- `GetRealmName()` returned an empty string; settled in ADR 0005 (realm part pinned empty).
- Whether and how `ReplicateItems` is throttled.
- Whether `GetActiveGameMode()` differs between rulesets: it does not (1 on Normal and PvP); settled in ADR 0005.
