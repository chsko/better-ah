# In Forever, a market is ruleset plus faction, and the realm part stays empty

ADR 0003 keys every price by realm, ruleset and faction. In Forever, `GetRealmName()` returns an empty string (ADR 0004), and rulesets take the place of realms. So the realm part of the market key is always empty, and a market is identified by the ruleset plus faction.

The ruleset is named from the game rules that are on: `C_GameRules.IsGameRuleActive(Enum.GameRule.HardcoreRuleset / PvPRuleset / RPRuleset)` gives "Hardcore", "Roleplay PvP", "Roleplay", "PvP" or "Normal", the same way TradeSkillMaster reads it on Forever. We first used `GetActiveGameMode()`, but the self-test showed 1 on both a Normal and a PvP character (and `GetForeverExperiencePreset()` is 1 on both too), so it can't tell rulesets apart. `GetCurrentGameModeRecordID()` does differ (15 on Normal, 14 on PvP), but it is an opaque record id; the rule names say what they mean. A client without these rules, or whose rules can't be read, falls back to `GetActiveGameMode()`.

We pinned this on purpose instead of using whichever realm source answers first, because the key must never change between sessions. If a patch later filled in `GetNormalizedRealmName`, or we used the character's home server from `UnitGUID`, every saved price would be orphaned, and alts with different home servers would split one auction house into several markets. The self-test still reports every realm source, so we can see if one starts answering.

The three neutral auction houses (Gadgetzan, Booty Bay and Everlook) form their own market, with faction "Neutral". They are recognised by the map the player is on (Tanaris, Stranglethorn Vale, Winterspring), since each of those zones has only that one auction house.

## Consequences

- If Forever turns out to have several separate auction houses within one ruleset and faction, their prices would mix. Revisit this ADR then, with a migration of saved prices.
- Prices saved under the old keys ("/1/Horde", "/1/Alliance") are not moved: they could belong to either ruleset, and they predate price history anyway. Each market needs one fresh scan.
- Confirm in game that the PvP character's key is "/PvP/Alliance" and the Normal one's "/Normal/Horde" (#5).
