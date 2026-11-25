# Forever uses the C_AuctionHouse API only

`/bah selftest` in the Forever client (interface 16001, build 1.60.1.71091, EU, Horde; output on #3) found none of the legacy browse functions (`QueryAuctionItems`, `GetAuctionItemInfo` and friends) and every `C_AuctionHouse` function we probed, including `SendBrowseQuery` and `ReplicateItems`. So the Auction API adapter is written against `C_AuctionHouse` only, with no legacy fallback. The interface number 16001 in the toc is confirmed.

The probe only checks that these functions exist. Nobody has called `ReplicateItems` yet, so whether a full scan works on Forever, and how it is throttled, is not known.

Of the ruleset candidates, only `C_GameRules` answered: `GetActiveGameMode()` returned 1 and `IsHardcoreActive()` returned false. `C_Seasons` and `C_Realm.GetCurrentRulesetID` do not exist. One value from one ruleset doesn't show that `GetActiveGameMode` tells rulesets apart; that needs a run on a second ruleset.

## Open, carried to #5

- `GetRealmName()` returned an empty string, so the realm part of the market key (ADR 0003) needs another source.
- Whether `ReplicateItems` returns a full scan, and its throttle.
- Whether `GetActiveGameMode()` differs between rulesets.
