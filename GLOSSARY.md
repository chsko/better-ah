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

**Cancel scan**:
A check of your own auctions that finds the ones that have been undercut.

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
