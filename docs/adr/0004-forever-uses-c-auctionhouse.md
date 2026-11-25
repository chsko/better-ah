# Forever uses the C_AuctionHouse API only

`/bah selftest` in the Forever client (interface 16001, build 1.60.1.71091, EU, Horde; posted on #3) found none of the legacy browse functions (`QueryAuctionItems`, `GetAuctionItemInfo` and friends) and every `C_AuctionHouse` function we probed, including `ReplicateItems` for a full scan. So the Auction API adapter is written against `C_AuctionHouse` only, with no legacy fallback. The interface number 16001 in the toc is confirmed.

For the market key, the ruleset comes from `C_GameRules.GetActiveGameMode()` (it returned 1; `C_GameRules.IsHardcoreActive()` returned false), and region from `GetCurrentRegionName()`.

## Open

- `GetRealmName()` returned an empty string. The market key ticket (#5) probes the other realm sources (`GetNormalizedRealmName`, `C_Realm`, the player GUID) and picks one; until then a market may be identified by ruleset, region and faction alone.
- The `ReplicateItems` throttle on Forever is not measured yet. The first scan ticket (#5) records it in the self-test output.
