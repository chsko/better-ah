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

-- Records one scan of a market. listings is an array of
--   { item = "i:2589", name = "Linen Cloth", count = 20, buyout = 12000 }
-- where buyout is the whole stack's buyout in copper (0 or nil for bid-only listings).
-- Every item seen gets its lowest buyout per unit from this scan; items not in this scan
-- keep their earlier numbers and seen time. Returns the number of distinct items seen.
function PriceDB:recordScan(key, time, listings)
  local data = marketData(self, key, true)
  local seen, distinct = {}, 0
  for _, l in ipairs(listings) do
    local count = tonumber(l.count) or 0
    if l.item ~= nil and count > 0 then
      local entry = seen[l.item]
      if not entry then
        entry = { quantity = 0, listings = 0 }
        seen[l.item] = entry
        distinct = distinct + 1
      end
      if not entry.name and l.name and l.name ~= "" then entry.name = l.name end
      entry.quantity = entry.quantity + count
      entry.listings = entry.listings + 1
      local buyout = tonumber(l.buyout) or 0
      if buyout > 0 then
        local unit = math.floor(buyout / count)
        if not entry.lowest or unit < entry.lowest then entry.lowest = unit end
      end
    end
  end
  for item, entry in pairs(seen) do
    local old = data.items[item]
    data.items[item] = {
      name = entry.name or (old and old.name),
      lowest = entry.lowest,
      quantity = entry.quantity,
      listings = entry.listings,
      seen = time,
    }
  end
  data.lastScan = time
  return distinct
end

-- Time of the last scan of a market, or nil.
function PriceDB:lastScan(key)
  local data = marketData(self, key)
  return data and data.lastScan
end

-- Every item recorded for a market, as copies:
--   { item, name, lowest, quantity, listings, seen }
-- nameOf(item), if given, names items the scan didn't (the caller looks them up; this module stays
-- pure). Items are sorted by name, ignoring case; items still without a name come last, by item key.
function PriceDB:items(key, nameOf)
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
