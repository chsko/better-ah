# Forever client API reference

What the World of Warcraft: Forever client really offers an addon, for Better AH work. Read this before you call a
WoW API you have not used here before. Issue: [#152](https://github.com/chsko/better-ah/issues/152).

Facts are marked by where they come from:

- **dump**: [`api.json`](https://atraeau.github.io/WoW-Addons/api.json), a dump of the Forever client: interface 16001,
  build 1.60.1.70790, exported 2026-11-05. `systems` is Blizzard's generated API documentation. `globals` is a runtime
  list of every global **function** and every `C_` namespace with its members. It does not list tables, frames,
  constants or `Enum`, so a missing table name there proves nothing.
- **client**: Blizzard's own UI code from Christian's client, `_forever_\BlizzardInterfaceCode\Interface\AddOns`
  (exported 2026-11-25, live build), the same code as Gethe's
  [`wow-ui-source` `forever` branch](https://github.com/Gethe/wow-ui-source/tree/forever). Its
  `Blizzard_APIDocumentationGenerated` also carries the `HasRestrictions` flag, which the dump drops.
- **guide**: [WoW Forever Guides' addon developer guide](https://wowforeverguides.com/addons/developers) (7 pages,
  updated 2026-11-11). Community-tested on beta builds; it has nothing on the auction house or mail.
- **game**: checked in game by Christian; the issue or ADR is linked.

The `C_AuctionHouse` surface is the same in the dump (70790) and the client export (live): same functions, events and
enums.

## Client facts

| Fact | Value | Source |
| --- | --- | --- |
| TOC interface | `16001` (our `.toc` already declares it) | dump `meta.interface`, game (ADR 0004) |
| Build | 1.60.1.70790 in the dump; 1.60.1.71091 / 71139 on Christian's client | dump, game |
| Game type | `camelot`, in the Mainline family: Mainline UI and API (12.1.5 era), not Classic | client, guide |
| Project ID | `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT == 18`. Never branch on `WOW_PROJECT_MAINLINE` or `CLASSIC` | client, guide |
| Lua | 5.1: no `goto`, no `//`, no bitwise operators (use `bit.*`), no `require`, `io`, `os` | guide |
| Auction house | `C_AuctionHouse` only. No legacy `QueryAuctionItems` family | dump, game (ADR 0004) |
| Realm | `GetRealmName()` is empty: Forever is realmless, markets are ruleset + faction | game (ADR 0005) |
| Copper | `C_AuctionHouse.SupportsCopperValues()` is true: 1c undercuts work | game |
| Secrets | Midnight's secret values are on. Unit health and names can be secret; guard with `issecretvalue` | guide |
| Combat log | `COMBAT_LOG_EVENT_UNFILTERED` and `CombatLogGetCurrentEventInfo` are not for addons | guide |
| SavedVariables | Ready at `ADDON_LOADED` for our addon, never at file scope | guide |

## Globals that are gone, and what to use

The old Classic globals below are **not** in the dump's runtime list, and Blizzard's own Forever code never calls them
(there is no shim in `Blizzard_Deprecated` either). Code that reads them gets `nil`. Our specs fake the client, so a
spec that stubs one of these passes while the game fails: fake the `C_` call instead.

| Gone | Use | Notes |
| --- | --- | --- |
| `GetItemInfo` | `C_Item.GetItemInfo` | Same 18 returns. nil until cached (see Item info) |
| `GetItemInfoInstant` | `C_Item.GetItemInfoInstant` | Answers without the cache |
| `GetItemCount` | `C_Item.GetItemCount` | |
| `GetItemQualityColor` | `C_Item.GetItemQualityColor` | |
| `GetCoinTextureString` | `C_CurrencyInfo.GetCoinTextureString` | `GetMoneyString` (FormattingUtil) also exists |
| `GetAddOnMetadata`, `IsAddOnLoaded` | `C_AddOns.GetAddOnMetadata`, `C_AddOns.IsAddOnLoaded` | |
| `GetContainerItemInfo`, `GetContainerNumSlots`, `PickupContainerItem`, `UseContainerItem` | `C_Container.*` | |
| `CloseAuctionHouse` | `C_AuctionHouse.CloseAuctionHouse` | |
| `QueryAuctionItems`, `GetAuctionItemInfo`, `GetNumAuctionItems`, `PlaceAuctionBid`, `CanSendAuctionQuery`, `PostAuction`, `StartAuction`, `CancelAuction` (global), `GetOwnerAuctionItems` | `C_AuctionHouse.*` | Only `Core/Probes.lua` may name them, to prove they are gone |
| `GetSpellInfo` | `C_Spell.GetSpellInfo` (returns one table) | |
| `GetNumSkillLines`, `GetSkillLineInfo`, `GetTradeSkillInfo`, `GetCraftInfo` | `GetProfessions`, `GetProfessionInfo`, `C_TradeSkillUI.*` | Matters for crafting cost (#13) |

`PlaySoundFile` still exists, but the guide reports it fails on interface `.ogg` paths: use
`PlaySound(SOUNDKIT.X)`.

Globals that **do** exist and are safe: `GetMoney`, `GetServerTime`, `GetTime`, `UnitGUID`, `UnitFactionGroup`,
`UnitName` (may be secret on other units), `hooksecurefunc`, `ChatEdit_InsertLink`, `IsShiftKeyDown`, `GetCursorPosition`,
`issecretvalue`, `C_Timer`, `C_GameRules`, `C_Container`, `C_Item`, `C_Mail` and every mail global listed below.

Check a name yourself (run from the repo with the dump downloaded next to it):

```sh
python3 -c "import json,sys; g=json.load(open('api.json'))['globals']; [print(n, g.get(n,'ABSENT') if not isinstance(g.get(n),list) else 'namespace') for n in sys.argv[1:]]" GetItemInfo C_Item
python3 -c "import json; print('GetItemInfo' in json.load(open('api.json'))['globals']['C_Item'])"
```

In game: `/dump GetItemInfo` prints nil when it is gone; `/dump select(4, GetBuildInfo())` prints the interface number.

## Auction house (`C_AuctionHouse`)

### Calls with restrictions

These carry `HasRestrictions = true` in the live client's docs: call them **directly inside a hardware event** (a click,
a key, the mouse wheel) and on untainted state. A block does not throw: the game fires `ADDON_ACTION_BLOCKED` (or
`ADDON_ACTION_FORBIDDEN`) inside the call, shows "Interface action failed because of an AddOn", and bumps a counter
that only a full client restart clears (guide). `pcall` does not help and can hide the failure.

| Restricted | Not restricted (its partner) |
| --- | --- |
| `PlaceBid(auctionID, bid)` (buyouts too) | |
| `StartCommoditiesPurchase(itemID, quantity)` | `ConfirmCommoditiesPurchase(itemID, quantity)` |
| `PostItem`, `PostCommodity` | |
| `ConfirmPostItem`, `ConfirmPostCommodity` | |
| `CancelAuction(ownedAuctionID)` | `CanCancelAuction`, `GetCancelCost` |

What Blizzard's own UI does (client, `Blizzard_AuctionHouseUI/Shared`):

- `Blizzard_AuctionHouseFrame.lua`: a buyout calls `C_AuctionHouse.PlaceBid` from a StaticPopup's `OnAccept` (a click).
- `AuctionHouseFrameMixin:StartCommoditiesPurchase` shows its buy dialog **first**, then calls
  `C_AuctionHouse.StartCommoditiesPurchase(itemID, quantity, unitPrice)`, passing a **third argument, the unit price**
  shown to the player, which the generated docs do not list. Our `BrowseAPI:quoteCommodity` and `/bah` test command pass
  only two. That is a lead for the blocked quote in #112, not a proven cause.
- `AuctionHouseBuyDialogMixin:BuyNow` calls `ConfirmCommoditiesPurchase` and shows a 2 second "waiting" state.

What we learned in game: PlaceBid from a click and from `OnMouseWheel` both buy (#101); redrawing the view before
PlaceBid got it blocked, so send first and redraw after (#120, #130); after each purchase
`IsThrottledMessageSystemReady()` stays false until `AUCTION_HOUSE_THROTTLED_SYSTEM_READY` (#101).

### Throttles

| What | Limit | Source |
| --- | --- | --- |
| `ReplicateItems` (full scan) | One per 15 minutes per Battle.net account, shared with every addon (ForeverForge, TSM) | game (#114) |
| `SendSearchQuery`, `SendSellSearchQuery` | 100 calls a minute; "should not be used to query the entire auction house" | dump docs |
| Throttled message system | Check `IsThrottledMessageSystemReady()` before a query or buy; events `AUCTION_HOUSE_THROTTLED_MESSAGE_SENT`, `_QUEUED`, `_RESPONSE_RECEIVED`, `_DROPPED`, `AUCTION_HOUSE_THROTTLED_SYSTEM_READY` | dump |

### Functions by job

- **Full scan**: `ReplicateItems()`, then `REPLICATE_ITEM_LIST_UPDATE`; `GetNumReplicateItems()`,
  `GetReplicateItemInfo(i)` (18 separate return values: name, texture, count, qualityID, usable, level, levelType, minBid, minIncrement,
  buyoutPrice, bidAmount, highBidder, bidderFullName, owner, ownerFullName, saleStatus, itemID, hasAllInfo),
  `GetReplicateItemLink(i)`, `GetReplicateItemTimeLeft(i)`. Indexes run 0 to n-1 (`AuctionAPI`, game).
- **Browse**: `SendBrowseQuery({ searchString, sorts, minLevel, maxLevel, filters, itemClassFilters })`,
  `GetBrowseResults()` (returns an array of tables { itemKey, totalQuantity, minPrice, containsOwnerItem, appearanceLink }), `RequestMoreBrowseResults()`,
  `HasFullBrowseResults()`. Events `AUCTION_HOUSE_BROWSE_RESULTS_UPDATED`, `_ADDED`, `AUCTION_HOUSE_BROWSE_FAILURE`.
  Levels are **required** levels on Forever (`AuctionHouse_ShouldUseRequiredLevel()` returns true in the Camelot
  `Blizzard_AuctionData.lua`).
- **Item search** (one non-commodity item): `SendSearchQuery(itemKey, sorts, separateOwnerItems, minLevel, maxLevel)`,
  `GetNumItemSearchResults`, `GetItemSearchResultInfo(itemKey, i)` (returns one table { auctionID, quantity, buyoutAmount (per item),
  bidAmount, minBid, owners, totalNumberOfOwners, timeLeft, timeLeftSeconds, itemLink, containsOwnerItem, bidder }), `HasFullItemSearchResults`, `RequestMoreItemSearchResults`,
  `RefreshItemSearchResults`. Events `ITEM_SEARCH_RESULTS_UPDATED`, `_ADDED`.
- **Commodity search**: `SendSearchQuery` with the item's key, `GetNumCommoditySearchResults(itemID)`,
  `GetCommoditySearchResultInfo(itemID, i)` (returns one table { unitPrice, quantity, auctionID, owners,
  totalNumberOfOwners, numOwnerItems, timeLeftSeconds, containsOwnerItem }),
  `HasFullCommoditySearchResults`, `RequestMoreCommoditySearchResults`. Events `COMMODITY_SEARCH_RESULTS_UPDATED`,
  `_ADDED`.
- **Buy a commodity**: `StartCommoditiesPurchase` → `COMMODITY_PRICE_UPDATED(unitPrice, totalPrice)` or
  `COMMODITY_PRICE_UNAVAILABLE` → `ConfirmCommoditiesPurchase` → `COMMODITY_PURCHASE_SUCCEEDED` /
  `COMMODITY_PURCHASE_FAILED` / `COMMODITY_PURCHASED(itemID, quantity)`. `GetQuoteDurationRemaining()`,
  `CancelCommoditiesPurchase()`.
- **Buy or bid an item**: `PlaceBid` → `AUCTION_HOUSE_PURCHASE_COMPLETED(auctionID)`, `BID_ADDED`, or
  `AUCTION_HOUSE_SHOW_ERROR(error)`.
- **Post**: `GetItemCommodityStatus(location)`, `PostItem` / `PostCommodity` (return `needsConfirmation`; then
  `ConfirmPost*`), `CalculateItemDeposit` / `CalculateCommodityDeposit`, `GetAvailablePostCount`, `IsSellItemValid`.
  Events `AUCTION_HOUSE_AUCTION_CREATED`, `AUCTION_HOUSE_POST_WARNING`, `AUCTION_HOUSE_POST_ERROR`,
  `AUCTION_MULTISELL_START` / `_UPDATE` / `_FAILURE`. Duration index: 1 = 2h, 2 = 8h, 3 = 24h (game).
- **Own auctions**: `QueryOwnedAuctions(sorts)` → `OWNED_AUCTIONS_UPDATED`; `GetOwnedAuctions()`,
  `GetOwnedAuctionInfo(i)` (returns one table { auctionID, itemKey, itemLink, status, quantity, timeLeftSeconds,
  timeLeft, bidAmount, buyoutAmount, bidder }; status Active 0 / Sold 1; buyoutAmount is per unit while active, the whole sale once sold,
  game #131), `CanCancelAuction`, `GetCancelCost`, `CancelAuction` → `AUCTION_CANCELED`.
- **Bids**: `QueryBids`, `GetBids`, `GetBidInfo` (tables { auctionID, itemKey, itemLink, timeLeft, minBid, bidAmount,
  buyoutAmount, bidder }); `AUCTION_HOUSE_NEW_BID_RECEIVED`, `BIDS_UPDATED`. `QueryBids(sorts, auctionIDs)`
  lists the auctions you are the high bidder on plus the ids you name; an outbid auction only shows when named
  (Blizzard's window names the ids it saw this session), with someone else's GUID as bidder. minBid is the
  lowest new bid the server takes. Once outbid, nothing says what you bid: My bids (#95) keeps that itself.
- **Item keys**: `MakeItemKey(itemID, itemLevel, itemSuffix, battlePetSpeciesID)`, `GetItemKeyInfo(key, restrictQualityToFilter)`
  (returns one table { itemID, itemName, quality, iconFileID, isCommodity, isEquipment, isPet, ... }; may be nil until `ITEM_KEY_ITEM_INFO_RECEIVED`), `GetItemKeyFromItem(location)`,
  `GetItemKeyRequiredLevel`, `GetItemKeySampleLink`.
- **Notifications**: `AUCTION_HOUSE_SHOW_NOTIFICATION`, `AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION`,
  `AUCTION_HOUSE_SHOW_COMMODITY_WON_NOTIFICATION`, `AUCTION_HOUSE_AUCTIONS_EXPIRED`.
- **Window**: `AUCTION_HOUSE_SHOW`, `AUCTION_HOUSE_CLOSED`, `AUCTION_HOUSE_DISABLED`, `C_AuctionHouse.CloseAuctionHouse()`.

### Enums

| Enum | Values |
| --- | --- |
| `AuctionHouseError` | NotEnoughMoney 0, HigherBid 1, BidIncrement 2, BidOwn 3, ItemNotFound 4, RestrictedAccountTrial 5, HasRestriction 6, IsBusy 7, Unavailable 8, ItemHasQuote 9, DatabaseError 10, MinBid 11, NotEnoughItems 12, RepairItem 13, UsedCharges 14, QuestItem 15, BoundItem 16, ConjuredItem 17, LimitedDurationItem 18, IsBag 19, EquippedBag 20, WrappedItem 21, LootItem 22, DoubleBid 23, FavoritesMaxed 24, ItemNotAvailable 25, ItemBoundToAccountUntilEquip 26 |
| `AuctionHouseNotification` | BidPlaced 0, AuctionRemoved 1, AuctionWon 2, AuctionOutbid 3, AuctionSold 4, AuctionExpired 5 |
| `AuctionHouseSortOrder` | Price 0, Name 1, Level 2, Bid 3, Buyout 4, TimeRemaining 5 |
| `AuctionHouseFilter` | None 0, UncollectedOnly 1, UsableOnly 2, CurrentExpansionOnly 3, UpgradesOnly 4, ExactMatch 5, PoorQuality 6 … LegendaryQuality 11, ArtifactQuality 12, LegendaryCraftedItemOnly 13 |
| `AuctionHouseTimeLeftBand` | Short 0, Medium 1, Long 2, VeryLong 3 (seconds via `GetTimeLeftBandInfo`) |
| `ItemCommodityStatus` | Unknown 0, Item 1, Commodity 2 |
| `AuctionStatus` | Active 0, Sold 1 |

## Mail

`C_Mail` (live client): `CanCheckInbox()` → canCheck, secondsUntilAllowed; `HasInboxMoney(i)`; `IsCommandPending()`;
`SetOpeningAll(bool)`; `IsCODEnabled()`; `GetCraftingOrderMailInfo(i)`. The dump (70790) lacks `IsCODEnabled`, so the live
client is newer than the dump.

Globals (all in the dump): `CheckInbox`, `GetInboxNumItems`, `GetInboxHeaderInfo`, `GetInboxItem`, `GetInboxItemLink`,
`HasInboxItem`, `GetInboxText`, `GetInboxInvoiceInfo`, `TakeInboxMoney`, `TakeInboxItem`, `TakeInboxTextItem`,
`AutoLootMailItem`, `ReturnInboxItem`, `DeleteInboxItem`, `InboxItemCanDelete`, `CloseMail`, `HasNewMail`,
`SendMail`, `SetSendMailMoney`, `GetSendMailMoney`, `SetSendMailCOD`, `GetSendMailCOD`, `GetSendMailPrice`,
`ClickSendMailItemButton`, `GetSendMailItem`, `GetSendMailItemLink`, `HasSendMailItem`, `ClearSendMail`.

- `GetInboxHeaderInfo(i)` returns packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft, itemCount,
  wasRead, wasReturned, textCreated, canReply, isGM, firstItemQuantity, firstItemLink (from `MailFrame.lua`).
- `GetInboxInvoiceInfo(i)` returns invoiceType, itemName, playerName, bid, buyout, deposit, consignment, moneyDelay,
  etaHour, etaMin, count, commerceAuction.
- Events: `MAIL_SHOW`, `MAIL_CLOSED`, `MAIL_INBOX_UPDATE`, `MAIL_SUCCESS(itemID)`, `MAIL_FAILED(itemID)`,
  `CLOSE_INBOX_ITEM(i)`, `MAIL_OPEN_ALL_CANCELED`, `MAIL_SEND_SUCCESS`, `MAIL_SEND_INFO_UPDATE`, `MAIL_LOCK_SEND_ITEMS`,
  `MAIL_UNLOCK_SEND_ITEMS`, `SEND_MAIL_MONEY_CHANGED`, `SEND_MAIL_COD_CHANGED`, `UPDATE_PENDING_MAIL`.
- `C_SecureTransfer.SendMail`, `TakeMailMoney`, `GetMailSendInfo`, `GetMailReceiveInfo` have restrictions. Blizzard's
  Open All does not use them: it calls the plain globals above. `C_SecureTransfer` is not in the dump's runtime
  globals.

Sending (`Blizzard_MailFrame/MailFrame.lua`, `Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua`, read for #158):

- Attach: `C_Container.PickupContainerItem(bag, slot)` then `ClickSendMailItemButton()` (first free slot) or
  `ClickSendMailItemButton(i)`; `ClickSendMailItemButton(i, true)` clears slot `i`. `MAIL_SEND_INFO_UPDATE` follows;
  `GetSendMailItem(i)` returns name, itemID, texture, count, quality for `i` = 1..12. `ClearCursor()` drops a refused item.
- Bag buttons hand every modified click to the global `HandleModifiedItemClick(link, itemLocation)`; a plain Alt-click
  does nothing else, so a `hooksecurefunc` on it (with `IsAltKeyDown()`, `CursorHasItem()`) is how alt-click attaches.
- Send: `SetSendMailCOD(0)`, `SetSendMailMoney(0)`, then one of them, then `SendMail(to, subject, body, replyMailID)`.
  Postage `GetSendMailPrice()` is display only. COD needs an item, `C_Mail.IsCODEnabled()`, at most 10,000g.
- Failures: `UI_ERROR_MESSAGE(type, message)` then `MAIL_FAILED`; success: `MAIL_SEND_SUCCESS`. Some sends first
  show Blizzard's secure confirmation (`SECURE_TRANSFER_CONFIRM_SEND_MAIL`).

How Blizzard's Open All works (`Blizzard_MailFrame/MailFrame.lua`, `OpenAllMailMixin`), the model for #149:

- Taking mail needs **no hardware event**: only the first take runs inside the button click; every later take runs
  from `OnUpdate`.
- `C_Mail.SetOpeningAll(true)` at the start, `false` at the end.
- One take at a time: `TakeInboxMoney(i)` if the mail has money, else `TakeInboxItem(i, slot)` (slots from 16 down).
  Then wait `OPEN_ALL_MAIL_MIN_DELAY = 0.15` seconds and until `C_Mail.IsCommandPending()` is false.
- Skips GM mail (`isGM`) and COD mail; skips an item whose `MAIL_FAILED(itemID)` fired.
- Stops when `C_Container.CalculateTotalNumberOfFreeBagSlots() == 0`, on `MAIL_OPEN_ALL_CANCELED`, or when the
  frame hides. Restarts from mail 1 when `MAIL_INBOX_UPDATE` changes the count.
- Refresh: `C_Mail.CanCheckInbox()`; when false, `C_Timer.After(secondsUntilAllowed, …)` then `CheckInbox()`.

## Item info and caching

- `C_Item.GetItemInfo(id or link)` returns 18 values, or nothing until the item is cached (`MayReturnNothing`).
  `C_Item.GetItemNameByID`, `GetItemQualityByID`, `GetItemMaxStackSizeByID`, `GetItemIconByID` answer from the same
  cache. `C_Item.GetItemInfoInstant` answers at once (id, type, subtype, equip slot, icon, classID, subclassID).
- `C_Item.IsItemDataCachedByID(id)`, `C_Item.RequestLoadItemDataByID(id or link)`, then `ITEM_DATA_LOAD_RESULT(itemID,
  success)` (also `GET_ITEM_INFO_RECEIVED`). `success == false` means the server says the item does not exist: stop
  asking for it this session.
- Auction keys have their own cache: `GetItemKeyInfo` can be nil until `ITEM_KEY_ITEM_INFO_RECEIVED(itemID)`.

## UI and other client notes (guide)

- Frames that need a backdrop inherit `BackdropTemplate`. Timers are `C_Timer.After` / `C_Timer.NewTimer`.
- Options can use the Settings API (`Settings.RegisterAddOnCategory`), and a TOC `AddonCompartmentFunc` gives a
  button in the minimap's addon compartment.
- `InCombatLockdown()`: protected frames cannot be shown, hidden or moved in combat; queue until `PLAYER_REGEN_ENABLED`.
- Sounds: `PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)` and other `SOUNDKIT` keys, not file paths.
- Window art and templates for our own window: [addon-ui-design.md](../research/addon-ui-design.md).
- Drop-downs (#189): Forever ships Blizzard_Menu (game type `camelot`, see its `Camelot/` folder). The game's Settings
  panel uses `WowStyle2DropdownTemplate` (`CreateFrame("DropdownButton", nil, parent, "WowStyle2DropdownTemplate")`),
  filled with `dropdown:SetupMenu(function(dropdown, root) root:CreateRadio(text, isSelected, onSelect, data) end)`;
  `CreateCheckbox` keeps the list open, an entry with children opens a submenu, `SetScrollMode(height)` scrolls a long
  list, `OverrideText` sets the button's text. `WowStyle1ArrowDropdownTemplate` is the small arrow button; give it
  `menuMixin = MenuStyle2Mixin` for the same list. Better AH wraps all of this in `UI/Dropdown.lua`.
