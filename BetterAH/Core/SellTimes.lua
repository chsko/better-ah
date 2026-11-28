-- Sell times (#221, spec #215): the "best time to sell" hint for an item, from the data file the companion
-- app downloads (SellTimes.lua at the addon root, ns.SellTimesData, format in companion/core/src/export.rs).
-- Pure: everything is precomputed there; this only picks the entry for the current UTC weekday-hour and
-- words it in local time. Wording follows the mockup linked from #221. Specs in spec/sell_times_spec.lua.
local _, ns = ...
ns = ns or {}

local SellTimes = {}

SellTimes.VERSION = 1
SellTimes.WEEK = 168
-- Older data than this is left unused: the addon then behaves as without the file.
SellTimes.STALE = 3 * 86400
SellTimes.WORDS = { [0] = "Best", "Good", "Average", "Slow" }
SellTimes.DURATIONS = { [0] = 0, 2, 8, 24 }
SellTimes.DAYS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }
SellTimes.NOT_ENOUGH = "Not enough sales yet for a sell time."
SellTimes.NOTE = "Sales are estimated from listings that vanish early. Cancelled auctions count as sales."

-- The weekday-hour of a time: 0 is Monday 00:00 UTC, 167 Sunday 23:00 UTC (1970-01-01 was a Thursday).
function SellTimes.weekHour(unix)
  local h = math.floor(unix / 3600)
  return ((math.floor(h / 24) + 3) % 7) * 24 + h % 24
end

-- A hint code: betterBy * 16 + advice * 4 + rating. betterBy is nil for 1000 ("no sales expected now").
function SellTimes.decode(code)
  local rating = code % 4
  local advice = math.floor(code / 4) % 4
  local betterBy = math.floor(code / 16)
  if betterBy >= 1000 then betterBy = nil end
  return rating, advice, betterBy
end

-- The 168 codes of an entry's run-length encoded hints ({count, code, ...}), or nil if they don't add up.
function SellTimes.codes(hints)
  if type(hints) ~= "table" then return nil end
  local out = {}
  for i = 1, #hints - 1, 2 do
    local n, code = hints[i], hints[i + 1]
    if type(n) ~= "number" or type(code) ~= "number" or n < 0 or #out + n > SellTimes.WEEK then return nil end
    for _ = 1, n do out[#out + 1] = code end
  end
  if #out ~= SellTimes.WEEK then return nil end
  return out
end

-- "Sun 20:00" for a UTC weekday-hour plus the local offset in seconds (minutes kept for half-hour zones).
local function at(week, offset)
  local s = (week * 3600 + offset) % (SellTimes.WEEK * 3600)
  local day = math.floor(s / 86400)
  local h = math.floor(s / 3600) % 24
  local m = math.floor(s / 60) % 60
  return SellTimes.DAYS[day + 1], h, m
end

-- The best window in local time: long "Sun 20:00-23:00", short "Sun 20-23" ("Sun 19:30-22:30" with minutes).
function SellTimes.window(best, offset)
  local day, h, m = at(best, offset)
  local _, eh, em = at((best + 3) % SellTimes.WEEK, offset)
  local long = string.format("%s %02d:%02d-%02d:%02d", day, h, m, eh, em)
  if m ~= 0 then return long, long end
  return long, string.format("%s %d-%d", day, h, eh == 0 and 24 or eh)
end

-- A day's best window as hours only, in local time: long "19:00-22:00", short "19-22".
function SellTimes.hours(start, offset)
  local _, h, m = at(start, offset)
  local _, eh, em = at((start + 3) % SellTimes.WEEK, offset)
  local long = string.format("%02d:%02d-%02d:%02d", h, m, eh, em)
  if m ~= 0 then return long, long end
  return long, string.format("%d-%d", h, eh == 0 and 24 or eh)
end

-- Local time minus UTC in seconds, from date("*t", t) and date("!*t", t) for the same moment.
function SellTimes.offset(localT, utcT)
  if type(localT) ~= "table" or type(utcT) ~= "table" then return 0 end
  local days = (localT.yday or 0) - (utcT.yday or 0)
  if days > 1 then days = -1 elseif days < -1 then days = 1 end -- across New Year
  return ((days * 24 + (localT.hour or 0) - (utcT.hour or 0)) * 60 + (localT.min or 0) - (utcT.min or 0)) * 60
end

-- "Horde Normal" for the market key "/Normal/Horde" (ADR 0005).
function SellTimes.marketName(key)
  local ruleset, faction = tostring(key or ""):match("^/([^/]+)/([^/]+)$")
  return ruleset and (faction .. " " .. ruleset) or tostring(key or "")
end

-- data:   ns.SellTimesData (or nil)
-- id:     the item ID (a number)
-- market: the current market key; data for another market says nothing about this one
-- now:    the server time
-- offset: local time minus UTC in seconds, or a function(time) giving it at a time, so a best window
--         across a daylight saving change is shown in the time it will be then
-- Returns nil when there is nothing to say (no or stale data, another market), { none = true } when the
-- data is there but the item has too few sales, else the hint:
--   rating 0-3 and word ("Best", "Good", "Average", "Slow"), betterBy (percent or nil), duration (0 = wait,
--   else 2, 8 or 24 hours), window and short (the week's best window in local time), today and todayShort
--   (today's best 3 hours in local time, #263, or nil), inToday (now is in them), line (the Post screen's
--   sentence) and lead (its coloured start), better and advice (the parts of the tooltip's last row), price
--   (typical price in the best window, copper), sold, days, market (name).
function SellTimes.hint(data, id, market, now, offset)
  if type(data) ~= "table" or data.version ~= SellTimes.VERSION or type(data.items) ~= "table" then return nil end
  if not market or data.market ~= market then return nil end
  if type(now) ~= "number" or now <= 0 or type(data.generated) ~= "number" then return nil end
  if math.abs(now - data.generated) > SellTimes.STALE then return nil end
  local entry = data.items[id]
  local codes = entry and SellTimes.codes(entry.hints)
  local best = entry and entry.best
  if not (codes and type(best) == "number" and best >= 0 and best < SellTimes.WEEK) then return { none = true } end
  local nowWeek = SellTimes.weekHour(now)
  local untilBest = (best - nowWeek) % SellTimes.WEEK
  local offsetNow = offset
  if type(offset) == "function" then
    offsetNow = offset(now)
    offset = offset(now - now % 3600 + untilBest * 3600)
  end
  offset = tonumber(offset) or 0
  offsetNow = tonumber(offsetNow) or 0
  local rating, advice, betterBy = SellTimes.decode(codes[nowWeek + 1])
  local duration = SellTimes.DURATIONS[advice]
  local window, short = SellTimes.window(best, offset)
  local out = { rating = rating, word = SellTimes.WORDS[rating], betterBy = betterBy, duration = duration,
    window = window, short = short, price = entry.price, sold = entry.sold, days = data.days,
    market = SellTimes.marketName(data.market), generated = data.generated }
  -- Today's best 3 hours (#263): dayBest holds one UTC weekday-hour per day, Monday first, with days
  -- as the companion cut them (data.utcOffset hours east of UTC: Oslo). Shown in the player's local time.
  local dayOffset = type(data.utcOffset) == "number" and data.utcOffset * 3600 or offsetNow
  local day = (math.floor((now + dayOffset) / 86400) + 3) % 7
  local todayStart = type(entry.dayBest) == "table" and entry.dayBest[day + 1]
  if type(todayStart) == "number" and todayStart >= 0 and todayStart < SellTimes.WEEK then
    out.today, out.todayShort = SellTimes.hours(todayStart, offsetNow)
    out.inToday = (nowWeek - todayStart) % SellTimes.WEEK < 3
  end

  if rating == 0 then
    out.better, out.advice = "now", "post 2h now"
    out.lead = "Best time now."
    out.line = "Best time now. Post 2h."
    out.explain = "Now is in the best 3 hours of the week, so a 2h auction sells while it lasts."
    return out
  end
  if betterBy == nil then
    out.better = "no sales expected now"
  elseif betterBy == 0 then
    out.better = "about as good as now"
  else
    out.better = betterBy .. "% better"
  end
  if duration == 0 then
    out.advice = "wait until then"
    out.explain = "Even a 24h auction posted now would end before then."
  elseif untilBest < duration then
    out.advice = "post " .. duration .. "h"
    out.explain = string.format("A %dh auction posted now is still up when the best time starts.", duration)
  else
    -- A "good" hour far from the best window: nearly as good, so posting now is fine.
    out.advice = "or post 2h now"
    out.explain = "Now is nearly as good as the best time, so a 2h auction now is fine too."
  end
  -- The Post line, as in the mockups (#221, #263): the advice when there is one, else how much better the
  -- best time is.
  local tail = (duration == 0 or untilBest < duration) and out.advice or out.better
  if out.inToday and rating == 1 then
    out.lead = "Best time today."
    out.line = string.format("%s This week's best is %s, %s.", out.lead, short, tail)
  elseif out.today and todayStart == best then
    out.lead = out.word .. " now."
    out.line = string.format("%s Best today %s, the best of the week, %s.", out.lead, out.todayShort, tail)
  elseif out.today then
    out.lead = out.word .. " now."
    out.line = string.format("%s Best today %s, this week %s, %s.", out.lead, out.todayShort, short, tail)
  else
    out.lead = out.word .. " now."
    out.line = string.format("%s Best %s, %s.", out.lead, short, tail)
  end
  return out
end

-- The hover text under the Post screen's line: what the hint is based on. money formats copper.
function SellTimes.details(h, money)
  if h.none then
    return { "Better AH needs about a week of regular sales of an item before it can say when it sells best.",
      SellTimes.NOTE }
  end
  local lines = {
    string.format("%s, last %s.", h.market, h.days == 1 and "day" or ((h.days or 0) .. " days")),
    h.today and ("Best today: " .. h.today .. ".") or false,
    "Best this week: " .. h.window
      .. (h.price and h.price > 0 and money and (", typically " .. money(h.price) .. " each") or "") .. ".",
    string.format("Sold in that time: %d.", h.sold or 0),
    h.explain,
    SellTimes.NOTE,
  }
  local out = {}
  for _, l in ipairs(lines) do
    if l then out[#out + 1] = l end
  end
  return out
end

ns.SellTimes = SellTimes
return SellTimes
