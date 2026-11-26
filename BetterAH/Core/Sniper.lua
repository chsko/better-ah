-- Disenchant sniping (issue #12): the rules, without the game. Which auction house browse query finds a
-- target's greens, which browse results are worth a closer look, which auctions are buys, the queue of
-- finds, and the sniping session's spend. Game/SnipeAPI.lua runs the queries; UI/DisenchantView.lua
-- draws the Snipe tab.
local _, ns = ...
ns = ns or {}

local Sniper = {}

Sniper.UNCOMMON_FILTER = 8 -- Enum.AuctionHouseFilter.UncommonQuality
Sniper.PRICE_SORT = { { sortOrder = 0, reverseSort = false } } -- Enum.AuctionHouseSortOrder.Price
Sniper.LOOKUPS_PER_ROUND = 4 -- item searches after each browse, cheapest first (searches: 100 a minute)
Sniper.LOG_LINES = 50

-- Auction house item class filters per target item type (classID 4 armor, 2 weapons).
local CLASS_FILTERS = {
  cloth = { { classID = 4, subClassID = 1 } },
  leather = { { classID = 4, subClassID = 2 } },
  mail = { { classID = 4, subClassID = 3 } },
  plate = { { classID = 4, subClassID = 4 } },
  shield = { { classID = 4, subClassID = 6 } },
  jewelry = { { classID = 4, subClassID = 0 } },
  onehand = { { classID = 2, subClassID = 0 }, { classID = 2, subClassID = 4 }, { classID = 2, subClassID = 7 },
    { classID = 2, subClassID = 13 }, { classID = 2, subClassID = 15 } },
  twohand = { { classID = 2, subClassID = 1 }, { classID = 2, subClassID = 5 }, { classID = 2, subClassID = 6 },
    { classID = 2, subClassID = 8 }, { classID = 2, subClassID = 10 } },
  ranged = { { classID = 2, subClassID = 2 }, { classID = 2, subClassID = 3 }, { classID = 2, subClassID = 16 },
    { classID = 2, subClassID = 18 }, { classID = 2, subClassID = 19 } },
}
Sniper.CLASS_FILTERS = CLASS_FILTERS

-- The browse query for a target: its greens, of its types, by required level (what the auction house
-- filters on), cheapest first. band: { min, max, required = { min, max } } from Disenchant.greenBands.
-- Returns nil for a target with no item types.
function Sniper.browseQuery(target, band)
  local filters = {}
  for _, t in ipairs(ns.Targets.TYPES) do
    if target.types and target.types[t.id] then
      for _, f in ipairs(CLASS_FILTERS[t.id]) do
        filters[#filters + 1] = { classID = f.classID, subClassID = f.subClassID }
      end
    end
  end
  if #filters == 0 then return nil end
  return { searchString = "", minLevel = band.required.min, maxLevel = band.max < 99 and band.required.max or nil,
    filters = { Sniper.UNCOMMON_FILTER }, itemClassFilters = filters, sorts = Sniper.PRICE_SORT }
end

-- A browse result's item level: from the item's own details (fallback(itemID)) when they are loaded,
-- else from its item key. Classic-style auction houses work in required level, and the key's level
-- can be 0 there, or not the item level the bands are cut by.
local function levelOf(key, fallback)
  if not key then return nil end
  local level = fallback and tonumber(fallback(key.itemID))
  if not level or level <= 0 then level = tonumber(key.itemLevel) end
  if level and level > 0 then return level end
  return nil
end

-- Browse results worth a closer look: in the target's item level band (required level only roughly
-- follows it), with a cheapest price at or under the most to pay. maxOf(itemID) gives that most (nil:
-- not worth anything known). skip(itemKey, minPrice), optional, leaves out results looked up lately
-- with nothing cheaper since. levelFallback(itemID), optional, gives the item level when the key has
-- none. Cheapest first, at most LOOKUPS_PER_ROUND.
function Sniper.candidates(band, results, maxOf, skip, levelFallback)
  local out = {}
  for _, r in ipairs(results or {}) do
    local key = r.itemKey
    local level = levelOf(key, levelFallback)
    local max = key and maxOf(key.itemID)
    if level and level >= band.min and level <= band.max and max and max > 0 and (r.minPrice or 0) > 0
      and r.minPrice <= max and not (skip and skip(key, r.minPrice)) then
      out[#out + 1] = { itemKey = key, minPrice = r.minPrice, max = max, level = level }
    end
  end
  table.sort(out, function(a, b) return a.minPrice < b.minPrice end)
  while #out > Sniper.LOOKUPS_PER_ROUND do table.remove(out) end
  return out
end

-- Every browse result in the band with a known max price, as { itemKey, minPrice, max, delta }: delta is
-- how far the cheapest is under the max (negative: over it). For the "closest to your max prices" list.
function Sniper.near(band, results, maxOf, levelFallback)
  local out = {}
  for _, r in ipairs(results or {}) do
    local key = r.itemKey
    local level = levelOf(key, levelFallback)
    local max = key and maxOf(key.itemID)
    if level and level >= band.min and level <= band.max and max and max > 0 and (r.minPrice or 0) > 0 then
      out[#out + 1] = { itemKey = key, minPrice = r.minPrice, max = max, delta = max - r.minPrice,
        quantity = r.totalQuantity }
    end
  end
  return out
end

-- Why each browse result was left out of Sniper.near, counted by reason. reasonOf(itemID) gives the
-- item's max price and, when there is none, why: "loading", "type" or "worth". A max of 0 or less is
-- "profit" (the profit takes the whole worth), a result outside the band is "band", one with no buyout
-- "price", one without an item key "unreadable", and one that fits "fits". The counts add up to #results.
function Sniper.why(band, results, reasonOf, levelFallback)
  local out = {}
  for _, r in ipairs(results or {}) do
    local key, reason = r.itemKey, "fits"
    if not (key and key.itemID) then
      reason = "unreadable"
    else
      local max, no = reasonOf(key.itemID)
      local level = levelOf(key, levelFallback)
      if no == "loading" or no == "type" then
        reason = no
      elseif not level or level < band.min or level > band.max then
        reason = "band"
      elseif no then
        reason = no
      elseif not max or max <= 0 then
        reason = "profit"
      elseif (r.minPrice or 0) <= 0 then
        reason = "price"
      end
    end
    out[reason] = (out[reason] or 0) + 1
  end
  return out
end

Sniper.CLOSEST = 5

-- The listings to show from each target's last check (lists: a list of Sniper.near lists): what can be
-- bought first, most under the max first, then what is over it, closest first. At most n (CLOSEST).
function Sniper.closest(lists, n)
  local all = {}
  for _, list in ipairs(lists) do
    for _, e in ipairs(list) do all[#all + 1] = e end
  end
  table.sort(all, function(a, b)
    if a.delta ~= b.delta then return a.delta > b.delta end
    return a.itemKey.itemID < b.itemKey.itemID
  end)
  while #all > (n or Sniper.CLOSEST) do table.remove(all) end
  return all
end

-- The buys among an item's auctions ({ auctionID, unit, count, ownCount, link } from
-- PostingAPI.readListings): other sellers' buyouts at or under max.
function Sniper.buys(listings, max)
  local out = {}
  for _, l in ipairs(listings or {}) do
    if l.auctionID and (l.ownCount or 0) == 0 and l.unit and l.unit > 0 and l.unit <= max then
      out[#out + 1] = l
    end
  end
  return out
end

-- A sniping session: what was found, bought, passed and missed since Start, and what it cost.
-- saved: a table kept in BetterAHDB (the session survives a /reload), or nil for one in memory.
local Session = {}
Session.__index = Session
Sniper.Session = Session

function Session.new(saved, now)
  saved = saved or {}
  saved.started = saved.started or now
  saved.spent, saved.bought, saved.worth = saved.spent or 0, saved.bought or 0, saved.worth or 0
  saved.log = saved.log or {}
  -- taken: per auction ID, how many of its items were bought this session; math.huge once it is written
  -- off (refused, gone). Treated as no longer buyable (#145).
  return setmetatable({ saved = saved, finds = {}, seen = {}, looked = {}, taken = {} }, Session)
end

Sniper.RELOOK = 60 -- seconds before an item whose cheapest price hasn't changed is looked up again

local function keyText(key)
  return string.format("%s:%s:%s", tostring(key.itemID), tostring(key.itemLevel or 0), tostring(key.itemSuffix or 0))
end

-- Remembers that an item's auctions were looked up when its cheapest was minPrice.
function Session:lookedUp(key, minPrice, time)
  self.looked[keyText(key)] = { price = minPrice, time = time }
end

-- Keeps what an item's lookup saw (listings as Sniper.buys takes them): other sellers' buyouts at any
-- price, so Session:cheapest can say what is left once some are bought or gone (#145).
function Session:sawListings(key, listings)
  local l = self.looked[keyText(key)]
  if not l then return end
  l.left = {}
  for _, x in ipairs(listings or {}) do
    if x.auctionID and (x.ownCount or 0) == 0 and x.unit and x.unit > 0 then
      l.left[#l.left + 1] = { auctionID = x.auctionID, unit = x.unit, count = math.max(1, x.count or 1) }
    end
  end
end

-- The cheapest other seller's buyout left from an item's last lookup, leaving out what was bought or
-- written off since. nil: no lookup to go by. false: nothing left from it.
function Session:cheapest(key)
  local l = self.looked[keyText(key)]
  if not (l and l.left) then return nil end
  local best = false
  for _, x in ipairs(l.left) do
    if (self.taken[x.auctionID] or 0) < x.count and (not best or x.unit < best) then best = x.unit end
  end
  return best
end

-- Whether an item was looked up in the last RELOOK seconds with the same cheapest price: its auctions
-- are already found, passed or bought, so a lookup would waste a search and a slot.
function Session:fresh(key, minPrice, time)
  local l = self.looked[keyText(key)]
  return l ~= nil and l.price == minPrice and time - l.time < Sniper.RELOOK
end

function Session:log(time, kind, find, note)
  local log = self.saved.log
  table.insert(log, 1, { time = time, kind = kind, name = find and find.name, price = find and find.price,
    note = note })
  while #log > Sniper.LOG_LINES do table.remove(log) end
end

-- Adds a find ({ auctionID, name, link, price, worth, target }) unless it was already seen. Returns
-- true when it is new. Finds are kept with the most profit first.
function Session:add(find)
  if self.seen[find.auctionID] then return false end
  self.seen[find.auctionID] = true
  find.profit = (find.worth or 0) - find.price
  self.finds[#self.finds + 1] = find
  table.sort(self.finds, function(a, b)
    if a.profit ~= b.profit then return a.profit > b.profit end
    return a.auctionID < b.auctionID
  end)
  return true
end

function Session:next()
  return self.finds[1]
end

local function drop(self, auctionID)
  for i, f in ipairs(self.finds) do
    if f.auctionID == auctionID then return table.remove(self.finds, i) end
  end
  return nil
end

function Session:pass(time, auctionID)
  local f = drop(self, auctionID)
  if f then self:log(time, "passed", f) end
  return f
end

-- The auction house took the buyout.
function Session:bought(time, find)
  drop(self, find.auctionID)
  self.taken[find.auctionID] = (self.taken[find.auctionID] or 0) + 1
  local s = self.saved
  s.spent, s.bought, s.worth = s.spent + find.price, s.bought + 1, s.worth + (find.worth or 0)
  self:log(time, "bought", find)
end

-- The buyout failed (#96). kind (from SnipeAPI:buy) says what became of the auction:
-- "unsent" (the buy never reached the auction house, or the game blocked it): the find stays next, to
-- buy again, and the log says why it wasn't bought (once, not for every try with the same reason).
-- "unknown" (no answer) and "closed": the find goes, but the auction isn't written off: it may still be
-- listed, so it can be found again, and its item is looked up again on the next check of its target.
-- "refused" (the auction house said no): the find is gone for the session, so an auction the
-- auction house keeps refusing doesn't come back every check.
-- "gone" (the auction house couldn't find it: sold to someone else or taken down, #130): written off like
-- "refused". The other finds waiting from the same item's lookup are likely gone too (one seller's batch
-- that someone else bought), so they are dropped and not written off, and the item is looked up again
-- on the next check: what is still listed comes back as fresh finds. Returns how many were dropped.
function Session:missed(time, find, why, kind)
  if kind == "unsent" then
    local last = self.saved.log[1]
    if not (last and last.kind == "unsent" and last.name == find.name and last.note == why) then
      self:log(time, "unsent", find, why)
    end
    return 0
  end
  drop(self, find.auctionID)
  if kind == "refused" or kind == "gone" then self.taken[find.auctionID] = math.huge end
  local dropped = 0
  if kind == "unknown" or kind == "closed" then
    self.seen[find.auctionID] = nil
    if find.itemKey then self.looked[keyText(find.itemKey)] = nil end
  elseif kind == "gone" and find.itemKey then
    local key = keyText(find.itemKey)
    for i = #self.finds, 1, -1 do
      local f = self.finds[i]
      if f.itemKey and keyText(f.itemKey) == key then
        table.remove(self.finds, i)
        self.seen[f.auctionID] = nil
        dropped = dropped + 1
      end
    end
    self.looked[key] = nil
    if dropped > 0 then
      why = string.format("%s. Dropped %d more from the same search; looking again", why, dropped)
    end
  end
  self:log(time, "missed", find, why)
  return dropped
end

-- Whether a buy at price is allowed: under the session's spend cap (0: none) and leaving at least keep
-- copper on the character. Returns true, or false and why.
function Session:canBuy(price, money, cap, keep)
  cap, keep = tonumber(cap) or 0, tonumber(keep) or 0
  if cap > 0 and self.saved.spent + price > cap then return false, "over your spend cap for this session" end
  if money and money < price then return false, "not enough gold" end
  if money and money - price < keep then return false, "it would leave you under the gold you keep" end
  return true
end

function Session:summary()
  local s = self.saved
  return { started = s.started, spent = s.spent, bought = s.bought, worth = s.worth, profit = s.worth - s.spent }
end

ns.Sniper = Sniper
return Sniper
