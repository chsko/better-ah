-- Value history (#106): how disenchant values moved. Pure: callers pass prices and history in.
--
-- Two kinds of history:
--   * Snapshots: the disenchant materials' market values when a materials scan or a full scan finished,
--     the newest SNAPSHOTS kept per market. A full scan includes the materials (they are in its
--     listings on Forever), so it updates these values as a materials scan does (#143). Values compares
--     today's numbers with the snapshot before the latest one, to show what the last scan changed (+X in
--     green, -X in red).
--   * Daily series: a band's after-cut value per day, worked out from the daily material prices PriceDB
--     keeps (PriceDB.HISTORY_DAYS), so the chart has data from the first day. A day's value uses each
--     material's own point for that day, or its latest earlier point within MarketValue.DAYS.
local _, ns = ...
ns = ns or {}

local ValueHistory = {}

ValueHistory.SNAPSHOTS = 10

-- Saves the materials' prices now as a snapshot of the market. store is the saved table
-- (BetterAHDB.disenchant.snapshots), priceOf(materialID) a market value or nil, materials the list of
-- { id } to save (Disenchant.MATERIALS), kind which scan took it: "full" or "materials" (#143).
-- Returns the snapshot.
function ValueHistory.record(store, key, time, priceOf, materials, kind)
  store[key] = store[key] or {}
  local list = store[key]
  local prices = {}
  for _, m in ipairs(materials) do
    local v = tonumber(priceOf(m.id))
    if v and v > 0 then prices[m.id] = math.floor(v) end
  end
  local snapshot = { time = time, prices = prices, kind = kind }
  list[#list + 1] = snapshot
  while #list > ValueHistory.SNAPSHOTS do table.remove(list, 1) end
  return snapshot
end

-- The snapshot the changes are measured against: the one before the latest, or nil.
function ValueHistory.baseline(store, key)
  local list = store and key and store[key]
  return list and list[#list - 1] or nil
end

-- The newest snapshot: the one the shown prices come from, or nil.
function ValueHistory.latest(store, key)
  local list = store and key and store[key]
  return list and list[#list] or nil
end

-- The Values status line (#143, shortened in #197): which scan the prices come from and what the green and
-- red changes compare with, like "Full scan 3 min ago. Changes since 2 h ago." Either part is left out
-- without its snapshot; opts.skipSource leaves out the first (a materials scan's message says it).
-- Returns "" for nothing to say.
function ValueHistory.sourceText(latest, base, now, opts)
  local out = {}
  if latest and not (opts and opts.skipSource) then
    local names = { full = "Full scan", materials = "Materials scan" }
    out[#out + 1] = (names[latest.kind] or "Last scan") .. " " .. ns.Time.ago(latest.time, now) .. "."
  end
  if base then
    local ago = ns.Time.ago(base.time, now)
    out[#out + 1] = "Changes since " .. (ago == "just now" and "a moment ago" or ago) .. "."
  end
  return table.concat(out, " ")
end

-- A price lookup for a snapshot, like PriceDB's market value: priceOf(materialID) -> copper or nil.
function ValueHistory.priceLookup(snapshot)
  local prices = snapshot and snapshot.prices or {}
  return function(id) return prices[id] or prices[tostring(id)] end
end

-- A material's price on a day from its history (oldest first, { day, value }): that day's point, or the
-- latest earlier one within MarketValue.DAYS, or nil.
function ValueHistory.priceOn(history, day)
  local found
  for _, h in ipairs(history or {}) do
    if h.day > day then break end
    found = h
  end
  if found and day - found.day < ns.MarketValue.DAYS then return found.value end
  return nil
end

-- The after-cut value per day of one green band and class over the last `days` days up to today:
-- { { day, net } ... } oldest first. historyOf(materialID) gives the material's PriceDB history. A day
-- is left out when it has no value, or when a material priced today had no price that day (it would
-- count as nothing and drop the line for a reason that isn't the market).
function ValueHistory.bandSeries(band, class, historyOf, opts, today, days)
  local histories = {}
  local function history(id)
    if histories[id] == nil then histories[id] = historyOf(id) or {} end
    return histories[id]
  end
  local info = { quality = ns.Disenchant.UNCOMMON, class = class, level = band.min }
  local function valueOn(day)
    return ns.Disenchant.value(info, function(id) return ValueHistory.priceOn(history(id), day) end, opts)
  end
  local _, todayBreakdown = valueOn(today)
  local needed = {}
  for _, y in ipairs(todayBreakdown or {}) do
    if y.price then needed[#needed + 1] = y.id end
  end
  local out = {}
  for day = today - days + 1, today do
    local value, breakdown = valueOn(day)
    local ok = value ~= nil
    if ok then
      local priced = {}
      for _, y in ipairs(breakdown) do priced[y.id] = y.price ~= nil end
      for _, id in ipairs(needed) do ok = ok and priced[id] == true end
    end
    if ok then out[#out + 1] = { day = day, net = ns.Disenchant.net(value) } end
  end
  return out
end

-- A least-squares straight line through the series ({ day, net }): returns a function giving the line's
-- value on a day, and the line's change from the first to the last day of the series. nil with fewer
-- than two days.
function ValueHistory.trend(series)
  local n = #series
  if n < 2 then return nil end
  local sx, sy, sxx, sxy = 0, 0, 0, 0
  for _, p in ipairs(series) do
    sx, sy = sx + p.day, sy + p.net
    sxx, sxy = sxx + p.day * p.day, sxy + p.day * p.net
  end
  local denominator = n * sxx - sx * sx
  if denominator == 0 then return nil end
  local slope = (n * sxy - sx * sy) / denominator
  local intercept = (sy - slope * sx) / n
  local function at(day) return intercept + slope * day end
  return at, math.floor(slope * (series[n].day - series[1].day) + 0.5)
end

-- Where to draw a series in a chart of `days` days ending today: each point as x and y from 0 to 1, the
-- trend line's two ends the same way, and the low and high values the y axis spans (the trend line's ends
-- included, so it is drawn at its true slope). nil for no points.
function ValueHistory.layout(series, today, days)
  if #series == 0 then return nil end
  local at = ValueHistory.trend(series)
  local low, high = math.huge, -math.huge
  for _, p in ipairs(series) do
    low, high = math.min(low, p.net), math.max(high, p.net)
  end
  local first, last = series[1].day, series[#series].day
  local lineFrom, lineTo = at and at(first), at and at(last)
  if at then
    low = math.min(low, math.floor(math.min(lineFrom, lineTo)))
    high = math.max(high, math.ceil(math.max(lineFrom, lineTo)))
  end
  local span = high - low
  local function y(v)
    if span <= 0 then return 0.5 end
    return math.max(0, math.min(1, (v - low) / span))
  end
  local function x(day)
    if days <= 1 then return 1 end
    return (day - (today - days + 1)) / (days - 1)
  end
  local out = { low = low, high = high, points = {} }
  for i, p in ipairs(series) do out.points[i] = { x = x(p.day), y = y(p.net) } end
  if at then out.trend = { { x = x(first), y = y(lineFrom) }, { x = x(last), y = y(lineTo) } } end
  return out
end

ns.ValueHistory = ValueHistory
return ValueHistory
