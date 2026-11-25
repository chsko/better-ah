-- Price database: scans recorded per market (ADR 0001, ADR 0003). Pure: callers pass plain
-- listing tables and a time; nothing here calls the WoW API.
local _, ns = ...
ns = ns or {}

local PriceDB = {}
PriceDB.__index = PriceDB

-- store is the saved-variables table to keep data in (BetterAHDB.prices in the client).
function PriceDB.new(store)
  return setmetatable({ store = store or {} }, PriceDB)
end

local function marketData(self, key, create)
  local data = self.store[key]
  if not data and create then
    data = { items = {} }
    self.store[key] = data
  end
  return data
end

local MarketValue = function() return ns.MarketValue end
PriceDB.HISTORY_DAYS = 30
PriceDB.MAX_PRICE = 2 ^ 31 - 1 -- the most copper a character can hold; imports above it are refused

-- Records one scan of a market. listings is an array of
--   { item = "i:2589", name = "Linen Cloth", count = 20, buyout = 12000 }
-- where buyout is the whole stack's buyout in copper (0 or nil for bid-only listings).
-- Every item seen gets its lowest buyout per unit, its quantity and a market value point for today;
-- items not in this scan keep their earlier numbers and seen time. Returns the number of distinct items.
function PriceDB:recordScan(key, time, listings)
  local seen, order = {}, {}
  for _, l in ipairs(listings) do
    local count = tonumber(l.count) or 0
    if l.item ~= nil and count > 0 then
      local entry = seen[l.item]
      if not entry then
        entry = { quantity = 0, listings = {} }
        seen[l.item] = entry
        order[#order + 1] = l.item
      end
      if not entry.name and l.name and l.name ~= "" then entry.name = l.name end
      entry.quantity = entry.quantity + count
      entry.listings[#entry.listings + 1] = { count = count, buyout = tonumber(l.buyout) or 0 }
    end
  end
  local points = {}
  for _, item in ipairs(order) do
    local entry = seen[item]
    local value, info = MarketValue().scanValue(entry.listings)
    points[item] = {
      name = entry.name, value = value, lowest = info and info.lowest, quantity = entry.quantity,
      listings = #entry.listings, units = info and info.units, used = info and info.used,
      dropped = info and info.dropped,
    }
  end
  self:recordPoints(key, time, points, "scan")
  return #order
end

-- Records imported prices (ADR 0001): prices maps item to { value = copper, name = optional }.
-- They go through recordPoints like a scan, so market value and history treat them the same way.
-- Returns the number of items taken.
function PriceDB:importPrices(key, time, prices)
  local points, n = {}, 0
  for item, p in pairs(prices) do
    local value = tonumber(p.value)
    if value and value >= 1 and value <= PriceDB.MAX_PRICE then
      points[item] = { name = p.name, value = math.floor(value) }
      n = n + 1
    end
  end
  self:recordPoints(key, time, points, "import")
  return n
end

-- History is kept per item as one short string, "day:value:points;day:value:points", oldest day
-- first. A full scan has about 7,000 items, so a table per day per item would make the saved
-- variables tens of megabytes; this keeps 30 days at a few hundred bytes per item.
local function decodeHistory(str)
  local out = {}
  for day, value, points in string.gmatch(str or "", "(%-?%d+):(%d+):(%d+)") do
    out[#out + 1] = { day = tonumber(day), value = tonumber(value), points = tonumber(points) }
  end
  return out
end

local function encodeHistory(history)
  local parts = {}
  for i, h in ipairs(history) do parts[i] = string.format("%d:%d:%d", h.day, h.value, h.points) end
  return table.concat(parts, ";")
end

-- Adds a value to the item's point for that day, keeping days in order and the newest 30.
local function addToHistory(e, day, value)
  local history = decodeHistory(e.hist)
  local at = #history + 1
  for i = #history, 1, -1 do
    if history[i].day == day then
      local h = history[i]
      h.value = math.floor((h.value * h.points + value) / (h.points + 1) + 0.5)
      h.points = h.points + 1
      at = nil
      break
    elseif history[i].day < day then
      break
    end
    at = i
  end
  if at then table.insert(history, at, { day = day, value = value, points = 1 }) end
  local newest = history[#history].day
  while history[1].day <= newest - PriceDB.HISTORY_DAYS do table.remove(history, 1) end
  e.hist = encodeHistory(history)
end

-- The one way prices get in. points maps item to
--   { value, name, lowest, quantity, listings, units, used, dropped } (all optional but value)
-- and each value is added to the item's history point for that day (averaged with earlier points
-- of the same day). A scan also updates the item's lowest buyout, quantity and seen time, and keeps
-- how its value was worked out; an import only notes the day it came in.
function PriceDB:recordPoints(key, time, points, source)
  local data = marketData(self, key, true)
  local day = MarketValue().day(time)
  for item, p in pairs(points) do
    local e = data.items[item]
    if not e then
      e = {}
      data.items[item] = e
    end
    if p.name and p.name ~= "" then e.name = p.name end
    if source == "scan" then
      e.lowest, e.quantity, e.listings, e.seen = p.lowest, p.quantity, p.listings, time
      if p.value then e.scan = string.format("%d:%d:%d:%d", day, p.units or 0, p.used or 0, p.dropped or 0) end
    elseif p.value and (not e.imported or day > e.imported) then
      e.imported = day
    end
    if p.value then addToHistory(e, day, p.value) end
  end
  if source == "scan" then data.lastScan = time end
  data.updated = (data.updated or 0) + 1
end

-- Changes whenever anything about a market's prices changes; for callers that cache.
function PriceDB:version(key)
  local data = marketData(self, key)
  return data and data.updated or 0
end

-- An item's market value on a market at time now, or nil. The second value explains it:
--   { days, oldest } from MarketValue.smooth, plus
--   scan = { day, units, used, dropped } for the item's latest scan with buyouts, if any, and
--   imported = the day of its latest imported price, if any.
function PriceDB:marketValue(key, item, now)
  local data = marketData(self, key)
  local e = data and data.items[item]
  if not (e and e.hist) then return nil end
  local value, info = MarketValue().smooth(decodeHistory(e.hist), now)
  if not value then return nil end
  if e.scan then
    local day, units, used, dropped = string.match(e.scan, "^(%-?%d+):(%d+):(%d+):(%d+)$")
    if day then
      info.scan = { day = tonumber(day), units = tonumber(units), used = tonumber(used), dropped = tonumber(dropped) }
    end
  end
  info.imported = e.imported
  return value, info
end

-- Time of the last scan of a market, or nil.
function PriceDB:lastScan(key)
  local data = marketData(self, key)
  return data and data.lastScan
end

-- An item's history on a market, oldest day first: { day, value, points } per day.
function PriceDB:history(key, item)
  local data = marketData(self, key)
  local e = data and data.items[item]
  return decodeHistory(e and e.hist)
end

-- Every item recorded for a market, as copies:
--   { item, name, lowest, quantity, listings, seen, value }
-- value is the market value at time now, when now is given.
-- nameOf(item), if given, names items the scan didn't (the caller looks them up; this module stays
-- pure). Items are sorted by name, ignoring case; items still without a name come last, by item key.
function PriceDB:items(key, nameOf, now)
  local data = marketData(self, key)
  local out = {}
  if not data then return out end
  local sortKey = {}
  for item, e in pairs(data.items) do
    local name = e.name
    if not name and nameOf then
      name = nameOf(item)
      if type(name) ~= "string" or name == "" then name = nil end
    end
    local copy = {
      item = item, name = name, lowest = e.lowest, quantity = e.quantity, listings = e.listings, seen = e.seen,
      value = now and e.hist and MarketValue().smooth(decodeHistory(e.hist), now) or nil,
    }
    out[#out + 1] = copy
    sortKey[copy] = name and name:lower()
  end
  table.sort(out, function(a, b)
    local ak, bk = sortKey[a], sortKey[b]
    if (ak == nil) ~= (bk == nil) then return ak ~= nil end
    if ak and ak ~= bk then return ak < bk end
    return tostring(a.item) < tostring(b.item)
  end)
  return out
end

ns.PriceDB = PriceDB
return PriceDB
