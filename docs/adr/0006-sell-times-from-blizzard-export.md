# Sell times come from Blizzard's export, collected by a Rust companion app

ADR 0001 builds every price from our own in-game scans, because addons can't reach the internet and it wasn't clear whether Blizzard's web API covered Forever. It now does: since 2026-11-06 the Game Data API serves each Forever auction house's listings (`dynamic-forever-{region}`, `/data/wow/ruleset/{id}/auctions/{houseId}` and its `/commodities`), refreshed about hourly and readable without being logged in. Christian wants to know the best time to sell, and that needs data from the hours he isn't playing, so sell-time stats come from this export (spec #215).

The collector is a Rust app, `better-ah-companion`, in `companion/`, because Christian wants it to grow into a desktop GUI later. A pure library crate holds all the logic (sale inference, rolling stats, ranking and hints), and a CLI wraps it with HTTP and files. On GitHub Actions, `collect` runs every 15 minutes, so the PC can stay off. It publishes the stats on GitHub Pages and never commits to the repo: the stats and the previous snapshot live in the Actions cache, with the published copy as a fallback. On the PC, `sync` will copy a generated Lua data file into the addon (#220), and the addon will only look up and format precomputed values. So the page and the game can't disagree, and no logic is written twice.

Market value and everything else in ADR 0001 still come from our own scans. The export is used only for selling times, and it reaches the addon through a data file. That's the import seam ADR 0001 kept open.

## Consequences

- Sales are estimates. The export has no sales or sellers. A listing counts as sold only if it's gone sooner than its time-left bucket says it could have expired (MEDIUM at least 30 min, LONG at least 2 h, VERY_LONG at least 12 h left), so expiries aren't counted as sales. At an hourly cadence that misses listings bought in their last 2 hours, which undercounts 2-hour posts. Cancels look the same as sales and add noise.
- A corrupt or wrong-version cache entry fails every run (it never wipes stats). The fix is to delete the `ah-state-*` caches under Actions > Caches, so the next run falls back to the published copy.
- Only Horde Normal (house 114, EU) is collected for now.
- Blizzard's API terms want raw data refreshed or deleted within 30 days, so the stats cover a rolling 30 days, and only the latest raw snapshot is kept, in the Actions cache.
- The API is undocumented for Forever, and paths or house IDs can change. A failed fetch keeps the old stats and fails the run visibly.
- The repo now has a second toolchain. CI runs `cargo fmt`, `clippy` and `cargo test` next to luacheck and busted.
