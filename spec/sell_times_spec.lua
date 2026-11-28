local helper = require("spec.helper")

describe("SellTimes (#221)", function()
  local SellTimes = helper.load("BetterAH/Core/SellTimes.lua").SellTimes
  -- 2026-11-16 00:00 UTC, a Monday: weekday-hour 0.
  local MONDAY = 1794787200
  local H = 3600
  local function code(betterBy, advice, rating) return (betterBy or 1000) * 16 + advice * 4 + rating end
  -- One code for every hour but `at`, which gets `special`.
  local function hints(at, special, other)
    other = other or code(50, 2, 2)
    local out = {}
    if at > 0 then out[#out + 1] = at; out[#out + 1] = other end
    out[#out + 1] = 1; out[#out + 1] = special
    if at < 167 then out[#out + 1] = 167 - at; out[#out + 1] = other end
    return out
  end
  -- Best window Sunday 19:00 UTC (weekday-hour 163).
  local function data(entryHints, extra)
    local d = { version = 1, generated = MONDAY + 2 * 86400, market = "/Normal/Horde", days = 26,
      items = { [16204] = { sold = 680, price = 9500, best = 163, hints = entryHints } } }
    for k, v in pairs(extra or {}) do d[k] = v end
    return d
  end
  local WED_10 = MONDAY + 2 * 86400 + 10 * H -- weekday-hour 58

  it("numbers weekday-hours from Monday 00:00 UTC like the companion app", function()
    assert.equal(0, SellTimes.weekHour(MONDAY))
    assert.equal(58, SellTimes.weekHour(WED_10 + 59 * 60))
    assert.equal(167, SellTimes.weekHour(MONDAY + 7 * 86400 - 1))
    assert.equal(0, SellTimes.weekHour(MONDAY + 7 * 86400))
  end)

  it("decodes codes and run lengths in the #218 format", function()
    assert.same({ 2, 2, 40 }, { SellTimes.decode(code(40, 2, 2)) })
    local r, a, b = SellTimes.decode(code(nil, 0, 3))
    assert.same({ 3, 0 }, { r, a })
    assert.is_nil(b, "1000 means no sales expected now")
    assert.equal(168, #SellTimes.codes({ 100, 5, 68, 9 }))
    assert.is_nil(SellTimes.codes({ 100, 5 }), "a broken entry is ignored")
  end)

  it("posts for the shortest duration still up at the best time, in local time (mockup B)", function()
    local sat23 = MONDAY + 5 * 86400 + 23 * H -- weekday-hour 143, best is 20h later
    local h = SellTimes.hint(data(hints(143, code(40, 3, 2)), { generated = sat23 }), 16204, "/Normal/Horde",
      sat23 + 600, 3600)
    assert.equal("Average", h.word)
    assert.equal(24, h.duration)
    assert.equal("Sun 20:00-23:00", h.window, "Oslo is UTC+1 in winter")
    assert.equal("Average now. Best Sun 20-23, post 24h.", h.line)
    local sun15 = MONDAY + 6 * 86400 + 15 * H -- 159, 4h before
    h = SellTimes.hint(data(hints(159, code(40, 2, 2)), { generated = sun15 }), 16204, "/Normal/Horde", sun15, 3600)
    assert.equal("Average now. Best Sun 20-23, post 8h.", h.line)
    local sun18 = MONDAY + 6 * 86400 + 18 * H -- 162, 1h before
    h = SellTimes.hint(data(hints(162, code(10, 1, 1)), { generated = sun18 }), 16204, "/Normal/Horde", sun18, 3600)
    assert.equal("Good now. Best Sun 20-23, post 2h.", h.line)
  end)

  it("says when now is the best time", function()
    local sun19 = MONDAY + 6 * 86400 + 19 * H
    local h = SellTimes.hint(data(hints(163, code(0, 1, 0)), { generated = sun19 }), 16204, "/Normal/Horde", sun19, 0)
    assert.equal(0, h.rating)
    assert.equal("Best time now. Post 2h.", h.line)
  end)

  it("says wait when even 24h would end before the best time", function()
    local h = SellTimes.hint(data(hints(58, code(120, 0, 3))), 16204, "/Normal/Horde", WED_10, 3600)
    assert.equal(0, h.duration)
    assert.equal("Slow now. Best Sun 20-23, wait until then.", h.line)
    assert.matches("24h auction posted now would end", h.explain)
  end)

  it("doesn't claim a 2h auction lasts until a best time far away", function()
    local h = SellTimes.hint(data(hints(58, code(10, 1, 1))), 16204, "/Normal/Horde", WED_10, 3600)
    assert.equal("Good now. Best Sun 20-23, 10% better.", h.line)
  end)

  it("words no sales now and equal hours for the tooltip", function()
    local h = SellTimes.hint(data(hints(58, code(nil, 0, 3))), 16204, "/Normal/Horde", WED_10, 0)
    assert.equal("no sales expected now", h.better)
    assert.equal("wait until then", h.advice)
    h = SellTimes.hint(data(hints(58, code(0, 1, 1))), 16204, "/Normal/Horde", WED_10, 0)
    assert.equal("about as good as now", h.better)
  end)

  it("shows the best window in the local time it will have then, across a clock change", function()
    -- Saturday 12:00 UTC before a change; the window (Sunday 19:00 UTC) is after it.
    local sat12 = MONDAY + 5 * 86400 + 12 * H
    local asked
    local offset = function(t) asked = t; return t >= sat12 + 12 * H and 3600 or 7200 end
    local h = SellTimes.hint(data(hints(132, code(5, 0, 2)), { generated = sat12 }), 16204, "/Normal/Horde",
      sat12 + 1800, offset)
    assert.equal(MONDAY + 6 * 86400 + 19 * H, asked, "asked at the window's start")
    assert.equal("Sun 20:00-23:00", h.window)
  end)

  it("ignores a broken entry or a missing clock", function()
    assert.same({ none = true }, SellTimes.hint(data({ "x", 1 }), 16204, "/Normal/Horde", WED_10, 0))
    local bad = data(hints(58, 1)); bad.items[16204].best = "163"
    assert.same({ none = true }, SellTimes.hint(bad, 16204, "/Normal/Horde", WED_10, 0))
    assert.is_nil(SellTimes.hint(data(hints(58, 1)), 16204, "/Normal/Horde", 0, 0))
    assert.is_nil(SellTimes.hint(data(hints(58, 1)), 16204, nil, WED_10, 0), "market not known yet")
  end)

  it("converts to local time across midnight, the week's end and half-hour zones", function()
    assert.same({ "Sun 19:00-22:00", "Sun 19-22" }, { SellTimes.window(163, 0) })
    assert.same({ "Sun 23:00-02:00", "Sun 23-2" }, { SellTimes.window(163, 4 * H) })
    assert.same({ "Mon 01:00-04:00", "Mon 1-4" }, { SellTimes.window(163, 6 * H) }, "past Sunday wraps to Monday")
    assert.same({ "Sun 11:00-14:00", "Sun 11-14" }, { SellTimes.window(163, -8 * H) })
    assert.same({ "Mon 00:30-03:30", "Mon 00:30-03:30" }, { SellTimes.window(163, 5.5 * H) })
    assert.equal("Sun 21-24", select(2, SellTimes.window(162, 3 * H)))
  end)

  it("says nothing without data, with stale data, for another market or another format", function()
    assert.is_nil(SellTimes.hint(nil, 16204, "/Normal/Horde", WED_10, 0))
    assert.is_nil(SellTimes.hint(data(hints(58, 1)), 16204, "/Normal/Horde", WED_10 + 4 * 86400, 0))
    assert.is_nil(SellTimes.hint(data(hints(58, 1)), 16204, "/PvP/Alliance", WED_10, 0))
    assert.is_nil(SellTimes.hint(data(hints(58, 1), { version = 2 }), 16204, "/Normal/Horde", WED_10, 0))
  end)

  it("says there is too little data for an item without hints", function()
    assert.same({ none = true }, SellTimes.hint(data(hints(58, 1)), 720, "/Normal/Horde", WED_10, 0))
    assert.same({ none = true }, SellTimes.hint(data({ 3, 1 }), 16204, "/Normal/Horde", WED_10, 0))
  end)

  it("works out the local offset from date tables, also across New Year", function()
    assert.equal(3600, SellTimes.offset({ yday = 331, hour = 17, min = 5 }, { yday = 331, hour = 16, min = 5 }))
    assert.equal(-8 * 3600, SellTimes.offset({ yday = 330, hour = 20, min = 0 }, { yday = 331, hour = 4, min = 0 }))
    assert.equal(5.5 * 3600, SellTimes.offset({ yday = 1, hour = 5, min = 0 }, { yday = 365, hour = 23, min = 30 }))
    assert.equal(-3600, SellTimes.offset({ yday = 365, hour = 23, min = 0 }, { yday = 1, hour = 0, min = 0 }))
    assert.equal(0, SellTimes.offset(nil, nil))
  end)

  it("explains the numbers on hover", function()
    local h = SellTimes.hint(data(hints(58, code(120, 0, 3))), 16204, "/Normal/Horde", WED_10, 3600)
    local lines = SellTimes.details(h, function(c) return c .. "c" end)
    assert.equal("Horde Normal, last 26 days.", lines[1])
    assert.equal("Best this week: Sun 20:00-23:00, typically 9500c each.", lines[2])
    assert.equal("Sold in that time: 680.", lines[3])
    assert.matches("Cancelled auctions count as sales", lines[5])
    assert.matches("about a week", SellTimes.details({ none = true })[1])
  end)

  describe("today's best 3 hours (#263)", function()
    -- Saturday's best window starts 18:00 UTC (weekday-hour 138), 19:00 in Oslo (UTC+1).
    local DAY_BEST = { 20, false, 60, false, 116, 138, 163 }
    local function withDays(at, special, days)
      local d = data(hints(at, special), { generated = MONDAY + 5 * 86400 })
      d.items[16204].dayBest = days
      return d
    end

    it("names today's best hours and the week's on the Post line", function()
      local sat12 = MONDAY + 5 * 86400 + 12 * H -- weekday-hour 132
      local h = SellTimes.hint(withDays(132, code(40, 2, 2), DAY_BEST), 16204, "/Normal/Horde", sat12, 3600)
      assert.equal("19:00-22:00", h.today)
      assert.equal("19-22", h.todayShort)
      assert.is_false(h.inToday)
      assert.equal("Average now.", h.lead)
      assert.equal("Average now. Best today 19-22, this week Sun 20-23, 40% better.", h.line)
      local lines = SellTimes.details(h, function(c) return c .. "c" end)
      assert.equal("Best today: 19:00-22:00.", lines[2])
      assert.equal("Best this week: Sun 20:00-23:00, typically 9500c each.", lines[3])
    end)

    it("says so when now is in today's best hours and rates good", function()
      local sat19 = MONDAY + 5 * 86400 + 19 * H -- weekday-hour 139, inside 138-140
      local h = SellTimes.hint(withDays(139, code(40, 1, 1), DAY_BEST), 16204, "/Normal/Horde", sat19, 3600)
      assert.is_true(h.inToday)
      assert.equal("Best time today. This week's best is Sun 20-23, 40% better.", h.line)
      -- A weak day's best hours rated slow keep the rating word.
      h = SellTimes.hint(withDays(139, code(300, 0, 3), DAY_BEST), 16204, "/Normal/Horde", sat19, 3600)
      assert.equal("Slow now. Best today 19-22, this week Sun 20-23, wait until then.", h.line)
    end)

    it("doesn't repeat the window when today holds the week's best", function()
      local sun10 = MONDAY + 6 * 86400 + 10 * H -- weekday-hour 154
      local d = withDays(154, code(40, 3, 2), DAY_BEST)
      d.generated = sun10
      local h = SellTimes.hint(d, 16204, "/Normal/Horde", sun10, 3600)
      assert.equal("Average now. Best today 20-23, the best of the week, post 24h.", h.line)
    end)

    it("cuts days as the companion did, but shows hours in the player's time", function()
      -- A UK player (UTC+0) at 23:30 UTC Saturday: still Saturday there, but Sunday in Oslo.
      local sat2330 = MONDAY + 5 * 86400 + 23 * H + 1800
      local d = withDays(143, code(40, 2, 2), DAY_BEST)
      d.utcOffset = 1
      local h = SellTimes.hint(d, 16204, "/Normal/Horde", sat2330, 0)
      assert.equal("19:00-22:00", h.today, "Oslo's Sunday window, in UK time")
    end)

    it("uses the local day, which can differ from the UTC day", function()
      -- Monday 23:30 UTC is Tuesday 00:30 in Oslo: Tuesday has no best window.
      local d = withDays(23, code(40, 2, 2), DAY_BEST)
      d.generated = MONDAY + 23 * H
      local h = SellTimes.hint(d, 16204, "/Normal/Horde", MONDAY + 23 * H + 1800, 3600)
      assert.is_nil(h.today)
      assert.equal("Average now. Best Sun 20-23, 40% better.", h.line)
    end)

    it("ignores a broken dayBest and keeps the week's line", function()
      local sat12 = MONDAY + 5 * 86400 + 12 * H
      for _, days in ipairs({ "x", { 1, 2, 3, 4, 5, 999, 7 } }) do
        local h = SellTimes.hint(withDays(132, code(40, 2, 2), days), 16204, "/Normal/Horde", sat12, 3600)
        assert.is_nil(h.today)
      end
    end)
  end)
end)

describe("Sell time in game (#221)", function()
  local ns = helper.load("BetterAH/Core/SellTimes.lua")
  helper.load("BetterAH/Core/TooltipPrices.lua", ns)
  helper.load("BetterAH/Game/TooltipHook.lua", ns)
  helper.load("BetterAH/UI/PostView.lua", ns)
  local MONDAY = 1794787200

  it("colours the Post line's rating word and greys out too little data", function()
    local PostView = ns.PostView
    assert.equal("|cffffd100Average now.|r Best Sun 20-23, 40% better, post 8h.",
      PostView.sellTimeText({ rating = 2, word = "Average",
        line = "Average now. Best Sun 20-23, 40% better, post 8h." }))
    assert.equal("|cff3ce04aBest time now.|r Post 2h.",
      PostView.sellTimeText({ rating = 0, word = "Best", line = "Best time now. Post 2h." }))
    assert.equal("|cff3ce04aBest time today.|r This week's best is Sun 20-23, 40% better.",
      PostView.sellTimeText({ rating = 1, word = "Good", inToday = true, lead = "Best time today.",
        line = "Best time today. This week's best is Sun 20-23, 40% better." }))
    assert.equal("|cff9d9d9dNot enough sales yet for a sell time.|r", PostView.sellTimeText({ none = true }))
    assert.is_nil(PostView.sellTimeText(nil), "no data file: no line")
  end)

  it("reads the local offset from the client's date(), or uses UTC without it", function()
    local env = { date = function(fmt)
      if fmt == "!*t" then return { yday = 331, hour = 16, min = 0 } end
      return { yday = 331, hour = 17, min = 0 }
    end }
    assert.equal(3600, ns.TooltipHook.localOffset(env, MONDAY))
    assert.equal(0, ns.TooltipHook.localOffset({}, MONDAY))
  end)

  it("finds the item's hint in the data file on the addon", function()
    local addon = { SellTimesData = { version = 1, generated = MONDAY, market = "/Normal/Horde", days = 9,
      items = { [16204] = { sold = 40, price = 9500, best = 163, hints = { 168, 2 * 16 + 2 * 4 + 2 } } } } }
    local h = ns.TooltipHook.sellTime({}, addon, 16204, "/Normal/Horde", MONDAY + 60)
    assert.equal("Average", h.word)
    assert.is_nil(ns.TooltipHook.sellTime({}, {}, 16204, "/Normal/Horde", MONDAY), "no data file")
  end)
end)
