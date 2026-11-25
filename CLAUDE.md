# Better AH

An auction house addon for **World of Warcraft: Forever** (Blizzard's "Classic+" branch, level 60).
Goal: everything TradeSkillMaster does for the auction house, with improvements.

## Layout

- `BetterAH/` is the addon folder that gets copied into `Interface/AddOns/`. The `.toc` lists load order.
- `BetterAH/Core/` holds shared modules. Each file starts with `local addonName, ns = ...` and hangs
  its module on `ns` (for example `ns.Money`). No new globals except saved variables.
- `spec/` holds busted tests. `spec/helper.lua` loads an addon file with `(addonName, ns)` like the client does.
- `.claude/skills/` holds Matt Pocock's skills (installed with `npx skills@latest add mattpocock/skills`).

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

## Working rules

These come from the repo owner (`chsko`) and apply to everything we do, by any agent or person. They
override any skill that says otherwise.

- **Every change is based on a GitHub issue.** If the work has no issue yet, file one first. (Convention:
  branch as `issue-<n>-<slug>`.)
- **Conventional Commits** (https://www.conventionalcommits.org), for example `feat(selftest): add probe`
  or `docs: add working rules`.
- **Every commit references the issue being worked on**, for example `Refs #12`, or `Closes #12` on the
  commit that finishes it.
- **Adversarial review of every change first**, before it is committed or opened as a PR. In environments
  with the Codex-based `adversarial-review` plugin, use `/adversarial-review`. Otherwise give the diff, the
  issue and this file to a fresh reviewer agent told to find real defects and mark each finding blocking or
  non-blocking. Fix every blocking finding before committing.
- **Never merge, always rebase.** Never create a merge commit or a squash; if a pull request is merged on
  GitHub, use "Rebase and merge". Locally, integrate with
  `git rebase` or `git pull --rebase`, never `git merge`. This overrides the merge steps in `/implement-spec`.
- **Land on main by rebasing and pushing.** Once the adversarial review is done and its fixes are in,
  rebase the issue branch onto the latest `main`, run `luacheck .` and `busted` again, and push to `main`
  as a fast-forward. If the push is rejected because `main` moved, rebase again; never force-push. If it is
  rejected for any other reason, stop and report it. If a pull request exists and GitHub does not mark it
  merged, close it with a pointer to the commits on `main`.

## How we use the main flow

`/grill-with-docs` -> `/prototype` (whenever a question needs a runnable answer) -> `/to-spec` -> `/to-tickets`
-> `/implement` or `/implement-spec` -> `/retro`.

- Take the `/prototype` detour whenever a question is hard to settle on paper, and always for new UI:
  sketch the screen first (an HTML mockup is fine for layout, then a throwaway in-game frame on a
  `prototype/<name>` branch to check it fits the WoW client), and link the prototype from the spec.
- UI review: before a UI ticket is closed, review an in-game screenshot for hierarchy, consistency and
  readability (design-critique), and check button labels, tooltips and error text (ux-copy).

## Agent skills

### Issue tracker

Issues and specs live in GitHub Issues on `chsko/better-ah`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at the repo root, created lazily. See `docs/agents/domain.md`.
