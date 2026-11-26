-- Purchases (#119): what the player paid for items bought through Better AH (Snipe and Browse), so a
-- tooltip can show the paid price and the profit of selling. Pure: callers pass item keys, counts and
-- times; nothing here calls the WoW API. Specs in spec/purchases_spec.lua.
--
-- Kept per item ("i:<itemID>") as lots, oldest first: { t = time, n = units, c = copper for them all,
-- s = suffix id or nil }. The suffix keeps a green "of the Eagle" apart from one "of the Monkey", which
-- share an item ID and a market value but not a price paid.
--
-- Lots are never taken out when items leave: bought items spend time in the mail, on alts, in auctions
-- that expire and on the character, and a ledger that followed counts lost prices in each of those. So
-- the price asked for covers the newest lots, only as many units as the caller holds (newest first, as
-- the oldest are the likeliest to be gone), and lots older than MAX_DAYS go. The cost: an item bought,
-- sold and later looted again shows the old price until it ages out.
local _, ns = ...
ns = ns or {}

local Purchases = {}
Purchases.__index = Purchases

Purchases.MAX_LOTS = 100 -- per item; the oldest go first
Purchases.MAX_DAYS = 60

-- store is the saved-variables table (BetterAHDB.purchases in the client).
function Purchases.new(store)
  store = store or {}
  store.items = store.items or {}
  return setmetatable({ store = store }, Purchases)
end

-- The item ID and suffix ID of an item link or item string ("item:4251:0:0:0:0:0:-34:..."), or nil.
-- The suffix is nil when the item has none.
function Purchases.parseLink(link)
  if type(link) ~= "string" then return nil end
  local id, rest = link:match("item:(%-?%d+)([%-%d:]*)")
  id = tonumber(id)
  if not id then return nil end
  local fields = {}
  for f in (rest .. ":"):gmatch("([^:]*):") do fields[#fields + 1] = f end
  -- rest starts with ":", so fields[1] is empty; then enchant, four gems, and the suffix.
  local suffix = tonumber(fields[7] or "")
  if suffix == 0 then suffix = nil end
  return id, suffix
end

-- Records a buy: count units of item for copper in all, at time. suffix is the item's suffix id or nil.
function Purchases:add(item, suffix, count, copper, time)
  count, copper = math.floor(tonumber(count) or 0), math.floor(tonumber(copper) or 0)
  if type(item) ~= "string" or count <= 0 or copper < 0 then return false end
  local e = self.store.items[item]
  if not e then
    e = { lots = {} }
    self.store.items[item] = e
  end
  e.lots[#e.lots + 1] = { t = tonumber(time) or 0, n = count, c = copper, s = suffix }
  while #e.lots > Purchases.MAX_LOTS do table.remove(e.lots, 1) end
  return true
end

-- Records a buy from the auction house: count of the item (itemID, and its link when known, for the
-- suffix) for copper in all.
function Purchases:bought(itemID, link, count, copper, time)
  local id, suffix = Purchases.parseLink(link)
  id = id or tonumber(itemID)
  if not id then return false end
  return self:add("i:" .. id, suffix, count, copper, time)
end

-- Drops lots older than MAX_DAYS at time now, and items left with none.
function Purchases:prune(now)
  local cutoff = (tonumber(now) or 0) - Purchases.MAX_DAYS * 86400
  for item, e in pairs(self.store.items) do
    local kept = {}
    for _, lot in ipairs(e.lots or {}) do
      if (lot.t or 0) >= cutoff then kept[#kept + 1] = lot end
    end
    if #kept == 0 then self.store.items[item] = nil else e.lots = kept end
  end
end

-- What was paid for item, or nil when nothing is recorded. suffix: the item's suffix id; an item with a
-- suffix only counts lots of that suffix. held: how many the caller has (at least 1); the price covers
-- the newest lots up to that many units. Returns { unit = copper per unit (rounded), units = how many
-- that covers, at most held }.
function Purchases:paid(item, suffix, held)
  local e = self.store.items[item]
  if not e then return nil end
  local want = math.max(1, math.floor(tonumber(held) or 1))
  local n, c = 0, 0
  for i = #e.lots, 1, -1 do
    local lot = e.lots[i]
    if n >= want then break end
    if suffix == nil or lot.s == suffix then
      local take = math.min(lot.n, want - n)
      n, c = n + take, c + lot.c * take / lot.n
    end
  end
  if n == 0 then return nil end
  return { unit = math.floor(c / n + 0.5), units = n }
end

ns.Purchases = Purchases
return Purchases
