-- Market value (glossary): an item's typical price on a market. Pure: numbers in, numbers out.
--
-- Per scan, scanValue takes the item's listings and averages the cheapest part of them:
--   1. Sort every unit by its per-unit buyout (a stack of 20 counts as 20 units).
--   2. Leave out troll prices: with 3 or more units, any unit below a tenth of the median unit
--      price. One listing at 1 copper, or a cheap stack, can't drag the value down. (With 1 or 2 units
--      there is no telling which price is the odd one, so nothing is left out.)
--   3. Of the rest, always take the cheapest 15% of units, then keep taking up to 30% until the price
--      jumps by more than 20% from one unit to the next (the start of the expensive tail).
--   4. The scan's value is the average of those, rounded to whole copper (at least 1).
-- smooth then turns the per-day points into the market value: a weighted average over the last
-- 14 days in which today counts 14 times as much as 13 days ago. Days are UTC days (time / 86400).
local _, ns = ...
ns = ns or {}

local MarketValue = {}

MarketValue.MIN_SHARE = 0.15
MarketValue.MAX_SHARE = 0.30
MarketValue.JUMP = 1.2
MarketValue.TROLL = 0.1
MarketValue.MIN_UNITS_FOR_TROLLS = 3
MarketValue.DAYS = 14
MarketValue.DAY = 86400

-- listings: array of { count = n, buyout = whole stack's buyout in copper }. Bid-only listings
-- (no buyout) are ignored. Returns nil when no listing has a buyout, else
--   value, { units, used, dropped, lowest }
-- where units is every unit with a buyout, dropped is how many were left out as troll prices (step 2),
-- used is how many the average took (step 3) and lowest is the lowest unit buyout, trolls included.
function MarketValue.scanValue(listings)
  local groups, units = {}, 0
  for _, l in ipairs(listings) do
    local count, buyout = tonumber(l.count) or 0, tonumber(l.buyout) or 0
    if count > 0 and buyout > 0 then
      groups[#groups + 1] = { unit = buyout / count, count = count }
      units = units + count
    end
  end
  if units == 0 then return nil end
  table.sort(groups, function(a, b) return a.unit < b.unit end)
  -- Rounded up, never to 0: a stack of 10 for 5c is 1c each, not free.
  local lowest = math.max(1, math.ceil(groups[1].unit))

  -- Step 2: the median unit (the ceil(units / 2)-th cheapest) sets the troll line.
  local first, dropped = 1, 0
  if units >= MarketValue.MIN_UNITS_FOR_TROLLS then
    local middle, seen, median = math.ceil(units / 2), 0, nil
    for _, g in ipairs(groups) do
      seen = seen + g.count
      if seen >= middle then median = g.unit break end
    end
    while groups[first].unit < median * MarketValue.TROLL do
      dropped = dropped + groups[first].count
      first = first + 1
    end
  end

  -- Step 3: walk the remaining units cheapest first; groups keep it fast for big stacks.
  local rest = units - dropped
  local minUnits = math.max(1, math.ceil(rest * MarketValue.MIN_SHARE))
  local maxUnits = math.max(minUnits, math.floor(rest * MarketValue.MAX_SHARE))
  local used, sum, previous = 0, 0, nil
  for i = first, #groups do
    local g = groups[i]
    if used >= maxUnits then break end
    if used >= minUnits and g.unit > previous * MarketValue.JUMP then break end
    local n = math.min(g.count, maxUnits - used)
    sum = sum + g.unit * n
    used = used + n
    previous = g.unit
  end
  return math.max(1, math.floor(sum / used + 0.5)), { units = units, used = used, dropped = dropped, lowest = lowest }
end

function MarketValue.day(time)
  return math.floor(time / MarketValue.DAY)
end

-- points: array of { day = n, value = copper }, one per day. Returns nil when no point is within
-- the last 14 days before now, else value, { days = points used, oldest = age in days of the oldest }.
function MarketValue.smooth(points, now)
  local today = MarketValue.day(now)
  local total, weights, days, oldest = 0, 0, 0, 0
  for _, p in ipairs(points) do
    local age = today - p.day
    if age >= 0 and age < MarketValue.DAYS and p.value then
      local w = MarketValue.DAYS - age
      total = total + p.value * w
      weights = weights + w
      days = days + 1
      if age > oldest then oldest = age end
    end
  end
  if weights == 0 then return nil end
  return math.floor(total / weights + 0.5), { days = days, oldest = oldest }
end

ns.MarketValue = MarketValue
return MarketValue
