# Better AH

An auction house addon for World of Warcraft: Forever that scans, prices, posts, snipes and works out crafting and disenchant profit across all of a player's characters.

## Markets and prices

**Market**:
One auction house's listings, identified by realm, ruleset and faction. In Forever the realm part is empty and the neutral auction houses count as faction "Neutral" (ADR 0005). Prices from one market never mix with another's.
_Avoid_: server, realm (on their own)

**Scan**:
One pass that records the listings currently on a market's auction house.
_Avoid_: query, pull

**Listing**:
One auction seen in a scan: an item, a stack size, a buyout and its seller.
_Avoid_: auction (when meaning someone else's), entry

**Price database**:
The stored history of scans per market, and everything derived from it. It can also take in imported prices.
_Avoid_: AuctionDB, cache

**Market value**:
An item's typical price on a market: the average of the cheapest part of each scan's listings, leaving out troll prices far below the rest, smoothed over 14 days (UTC days).
_Avoid_: DBMarket, average price, AH price

**Sell times**:
When an item sells best on a market, by weekday and hour: estimated sales, typical price, min price and supply over a rolling 30 days, from Blizzard's hourly export (ADR 0006). Sales are estimated, since the export has no sales: a listing gone before its time ran out counts as sold.
_Avoid_: best time (on its own), sales history

**Companion app**:
`better-ah-companion`, the Rust app outside the game that collects sell times on GitHub Actions and syncs them to the addon (ADR 0006).
_Avoid_: desktop app, helper

## Selling

**Floor price**:
The lowest price you are willing to sell an item for. Defaults to 80% of market value.
_Avoid_: minimum price, min

**Undercut**:
Listing 1 copper below the cheapest competing listing (one that isn't yours). With no competing listing, the item is listed at its market value.

**Posting profile**:
The optional post limit ("Post at most") and duration remembered for an item. Without one, an item posts
everything in your bags for the default duration.
_Avoid_: operation, group settings

**Default duration**:
How long an item without its own duration in a posting profile is posted for. 24 hours until you pick 2 or 8
hours on the Settings view.

**Post limit**:
The most of an item to post per visit to the auction house ("Post at most"); the rest stay in your bags.
Empty means everything. A commodity posts as one listing of any size; other items post one auction per bag stack.
_Avoid_: stack size

**Post queue**:
The items in your bags that are ready to be posted right now.

**Essence swap**:
Combining three lesser essences into one greater, or splitting a greater into three lesser, before posting.
Post compares both at the prices it would post each form at and says when converting earns more (#234).
_Avoid_: merge

**My auctions**:
The view of every auction you have up on this character, where you also cancel them. It was called Cancel.

**Price check**:
A search of each item you have up, once, in the My auctions view, that finds the auctions that have been
undercut. It is what the spec called the cancel scan.
_Avoid_: cancel scan

## Buying

**Deal**:
A listing whose buyout is far enough below its value to be worth buying.
_Avoid_: snipe (as a noun), bargain

**Shopping list**:
A set of items you want to buy, each with a maximum price.

**Disenchant value**:
The expected sale value of the materials an item gives when disenchanted, averaged over all possible outcomes.
_Avoid_: DE price, destroy value

**Disenchant target**:
A rule for flagging disenchant deals: a minimum net profit in gold, a minimum profit percent, or both.
Its worth prices each material at the lower of its market value and the latest scan's cheapest listing
(from the last 24 hours), so max prices drop as soon as a material crashes.

**Net profit**:
What you actually earn: the sale value minus the 5% auction house cut and expected deposits, minus what you paid.
_Avoid_: margin, gross profit

## Characters and crafting

**Character record**:
What Better AH remembers about one of your characters: bags, bank, auctions and known recipes.
_Avoid_: alt data, profile

**Known recipe**:
A recipe one of your characters has learned, read from that character's profession window.

**Crafting profit**:
The net profit of crafting a known recipe: the crafted item's sale value minus the market value of its reagents.

## Mail

**Mailbox window**:
Better AH's own window at a mailbox, separate from the Better AH auction house window. It replaces Blizzard's mail frame unless that is turned off in Settings.
_Avoid_: mail frame (that is Blizzard's), mail view

**Mail kind**:
What a mail is, from the player's point of view: Sold, Bought, Outbid, Cancelled, Expired, Other (player mail), Letter (player mail with text, or from a Game Master) or COD (pay on delivery).
_Avoid_: mail type, category

**Send rule**:
A saved choice of what Send all mails to one of your characters: one item, a disenchant group (all enchanting mats, dusts, essences or shards) or an item type, a recipient, and how many of each item to keep in the bags. The most specific rule wins: an item, then a disenchant group, then a type. Rules never move gold. Saved per account.
_Avoid_: mail operation, mail group

**Send all**:
The Send tab's button that sends what every send rule matches in your bags right now, in mails of up to 12 stacks with one recipient each, one mail at a time, then reports what went out.
_Avoid_: mail all, auto mail
