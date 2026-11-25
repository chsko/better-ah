# Better AH

An auction house addon for **World of Warcraft: Forever** (Blizzard's "Classic+" branch, level 60).
Goal: everything TradeSkillMaster does for the auction house, with improvements.

## Layout

- `BetterAH/` is the addon folder that gets copied into `Interface/AddOns/`. The `.toc` lists load order.
- `BetterAH/Core/` holds shared modules. Each file starts with `local addonName, ns = ...` and hangs
  its module on `ns` (for example `ns.Money`). No new globals except saved variables.
- `spec/` holds busted tests. `spec/helper.lua` loads an addon file with `(addonName, ns)` like the client does.
- `ralph/` holds the agent loop (see "Workflow").

## Coding rules

- Lua 5.1 (the WoW client runtime). No `goto`, no integer division operator, no `utf8` library.
- Keep game logic (pricing, undercut rules, scan parsing, crafting cost) in **pure modules** that never
  call the WoW API. Pass data in, get data out. That is what we unit test.
- Isolate WoW API calls behind thin adapter modules (for example an `AuctionAPI` module) so the pure
  modules can be tested with fakes. Forever's AH API (legacy `QueryAuctionItems` vs `C_AuctionHouse`)
  must be confirmed before building on it.
- Money is always an integer number of copper.
- Add any new WoW global you read to `read_globals` in `.luacheckrc`.

## Testing (feedback loops)

Run both before every commit. Do not commit if either fails.

```sh
luacheck .
busted
```

Things that need the real client (frames, events, AH queries) cannot be tested here. Say so in the
issue or commit, and describe how to verify in game.

## Workflow

We follow Matt Pocock's workflow (https://github.com/mattpocock/skills) with GitHub issues as the tracker.

1. Plan: `/grill-me` on an idea, `/to-spec` to publish it as a spec issue, `/to-tickets` to split it into
   tracer-bullet issues with "Blocked by" edges. Issues ready for the loop get the `ready-for-agent` label.
2. Build: `ralph/once.sh` (one iteration, watched) or `ralph/afk.sh <n>` (unattended). Each iteration
   picks one unblocked `ready-for-agent` issue, implements it, runs the feedback loops, commits with
   `Closes #n`, closes the issue and appends to `progress.txt`.
3. Triage: `/triage` moves issues through the labels below.

Issue tracker config for the skills is in `docs/agents/issue-tracker.md`.
