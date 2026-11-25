# All price data is keyed by market (realm, ruleset, faction)

Christian plays several Forever rulesets, and their auction houses do not share prices. Every scan, market value and imported price is stored under a market key of realm, ruleset and faction from the start. Character records are stored per character, so alts on any market feed crafting and posting. Changing the saved-variables layout later would mean migrating players' data, so this is fixed now.
