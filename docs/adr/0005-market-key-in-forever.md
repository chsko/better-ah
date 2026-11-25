# In Forever, a market is ruleset plus faction, and the realm part stays empty

ADR 0003 keys every price by realm, ruleset and faction. In Forever, `GetRealmName()` returns an empty string (ADR 0004), and rulesets take the place of realms. So the realm part of the market key is always empty, and a market is identified by `C_GameRules.GetActiveGameMode()` plus faction.

We pinned this on purpose instead of using whichever realm source answers first, because the key must never change between sessions. If a patch later filled in `GetNormalizedRealmName`, or we used the character's home server from `UnitGUID`, every saved price would be orphaned, and alts with different home servers would split one auction house into several markets. The self-test still reports every realm source, so we can see if one starts answering.

The three neutral auction houses (Gadgetzan, Booty Bay and Everlook) form their own market, with faction "Neutral". They are recognised by the map the player is on (Tanaris, Stranglethorn Vale, Winterspring), since each of those zones has only that one auction house.

## Consequences

- If Forever turns out to have several separate auction houses within one ruleset and faction, their prices would mix. Revisit this ADR then, with a migration of saved prices.
- Whether `GetActiveGameMode()` really differs between rulesets is checked on #5.
