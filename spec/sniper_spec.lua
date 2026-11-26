local helper = require("spec.helper")

describe("Sniper", function()
  local ns = helper.load("BetterAH/Core/Money.lua")
  helper.load("BetterAH/Core/Targets.lua", ns)
  helper.load("BetterAH/Core/Sniper.lua", ns)
  local Sniper = ns.Sniper
  local band = { min = 26, max = 30, required = { min = 21, max = 25 } }

  local function target(types)
    local set = {}
    for _, id in ipairs(types) do set[id] = true end
    return { types = set, band = 26, profit = { kind = "percent", amount = 10 }, enabled = true }
  end

  it("browses a target's greens by type and required level, cheapest first", function()
    local q = Sniper.browseQuery(target({ "cloth", "ranged" }), band)
    assert.equal(21, q.minLevel)
    assert.equal(25, q.maxLevel)
    assert.same({ 8 }, q.filters)
    assert.same({ sortOrder = 0, reverseSort = false }, q.sorts[1])
    assert.equal(6, #q.itemClassFilters, "cloth, then five ranged subclasses")
    assert.same({ classID = 4, subClassID = 1 }, q.itemClassFilters[1])
    assert.same({ classID = 2, subClassID = 19 }, q.itemClassFilters[6])
    local top = Sniper.browseQuery(target({ "plate" }), { min = 61, max = 99, required = { min = 56, max = 94 } })
    assert.equal(56, top.minLevel)
    assert.is_nil(top.maxLevel, "the open top band has no ceiling")
    assert.is_nil(Sniper.browseQuery(target({}), band), "no types, nothing to browse")
  end)

  it("picks the cheap browse results in the band, cheapest first, a few at a time", function()
    local function result(id, level, price)
      return { itemKey = { itemID = id, itemLevel = level }, minPrice = price }
    end
    local maxOf = function(id) if id == 9 then return nil end return 1000 end
    local out = Sniper.candidates(band, {
      result(1, 28, 900), result(2, 28, 1001), result(3, 31, 10), result(4, 25, 10), result(9, 28, 5),
      result(5, 26, 300), result(6, 30, 400), result(7, 27, 500), result(8, 29, 600), result(10, 28, 0),
    }, maxOf)
    local ids = {}
    for i, c in ipairs(out) do ids[i] = c.itemKey.itemID end
    assert.same({ 5, 6, 7, 8 }, ids, "over max, out of band, worthless and free results are left out")
    assert.equal(1000, out[1].max)
    assert.same({}, Sniper.candidates(band, nil, maxOf))
  end)

  it("reads the item level from the item's details when the key has none", function()
    local results = { { itemKey = { itemID = 1, itemLevel = 0 }, minPrice = 500 },
      { itemKey = { itemID = 2, itemLevel = 0 }, minPrice = 600 }, { itemKey = { itemID = 3 }, minPrice = 700 } }
    local maxOf = function() return 1000 end
    local levels = { [1] = 28, [2] = 40 }
    local function levelOf(id) return levels[id] end
    assert.equal(0, #Sniper.candidates(band, results, maxOf), "no level, no guess")
    local out = Sniper.candidates(band, results, maxOf, nil, levelOf)
    assert.equal(1, #out)
    assert.equal(1, out[1].itemKey.itemID)
    assert.equal(1, #Sniper.near(band, results, maxOf, levelOf))
    local wrongKey = { { itemKey = { itemID = 1, itemLevel = 23 }, minPrice = 500 } }
    assert.equal(1, #Sniper.candidates(band, wrongKey, maxOf, nil, levelOf), "the details win over the key")
  end)

  it("lists the results nearest their max price, buyable ones first", function()
    local function result(id, level, price)
      return { itemKey = { itemID = id, itemLevel = level }, minPrice = price }
    end
    local maxOf = function(id) if id == 9 then return nil end return 1000 end
    local a = Sniper.near(band, { result(1, 28, 820), result(2, 28, 1300), result(3, 31, 10), result(9, 28, 5),
      result(4, 27, 1010) }, maxOf)
    assert.equal(3, #a, "out of band and unknown worth left out")
    assert.equal(180, a[1].delta)
    local b = Sniper.near(band, { result(5, 26, 990), result(6, 26, 2000), result(7, 26, 999) }, maxOf)
    local ids = {}
    for i, e in ipairs(Sniper.closest({ a, b })) do ids[i] = e.itemKey.itemID end
    assert.same({ 1, 5, 7, 4, 2 }, ids, "under the max (most first), then over it (closest first), five at most")
    assert.same({}, Sniper.closest({}))
  end)

  it("gives every browse result one reason, so the counts add up", function()
    local function result(id, level, price)
      return { itemKey = { itemID = id, itemLevel = level }, minPrice = price }
    end
    local reasons = { [1] = { nil, "loading" }, [2] = { nil, "type" }, [4] = { nil, "worth" }, [5] = { 0 },
      [6] = { 1000 }, [7] = { 1000 } }
    local reasonOf = function(id) local r = reasons[id] or { 1000 } return r[1], r[2] end
    local results = { result(1, 28, 10), result(2, 28, 10), result(3, 40, 10), result(4, 28, 10),
      result(5, 28, 10), result(6, 28, 0), result(7, 28, 900), { minPrice = 5 } }
    local why = Sniper.why(band, results, reasonOf)
    assert.same({ loading = 1, type = 1, band = 1, worth = 1, profit = 1, price = 1, fits = 1, unreadable = 1 }, why)
    local total = 0
    for _, n in pairs(why) do total = total + n end
    assert.equal(#results, total)
    assert.same({}, Sniper.why(band, nil, reasonOf))
  end)

  it("buys other sellers' buyouts at or under the max", function()
    local out = Sniper.buys({
      { auctionID = 1, unit = 900, count = 1, ownCount = 0 },
      { auctionID = 2, unit = 1000, count = 1, ownCount = 0 },
      { auctionID = 3, unit = 1001, count = 1, ownCount = 0 },
      { auctionID = 4, unit = 500, count = 1, ownCount = 1 },
      { unit = 500, count = 1, ownCount = 0 },
      { auctionID = 6, unit = 0, count = 1, ownCount = 0 },
    }, 1000)
    assert.equal(2, #out)
    assert.equal(1, out[1].auctionID)
    assert.equal(2, out[2].auctionID)
  end)

  describe("Session", function()
    it("queues finds once, most profit first", function()
      local s = Sniper.Session.new(nil, 100)
      assert.is_true(s:add({ auctionID = 1, name = "A", price = 900, worth = 1000 }))
      assert.is_true(s:add({ auctionID = 2, name = "B", price = 500, worth = 1000 }))
      assert.is_false(s:add({ auctionID = 1, name = "A", price = 900, worth = 1000 }), "already seen")
      assert.equal(2, s:next().auctionID)
      assert.equal(500, s:next().profit)
      s:pass(110, 2)
      assert.equal(1, s:next().auctionID)
      assert.is_false(s:add({ auctionID = 2, name = "B", price = 500, worth = 1000 }), "a pass lasts the session")
      assert.equal("passed", s.saved.log[1].kind)
    end)

    it("counts what it bought and logs what it missed", function()
      local saved = {}
      local s = Sniper.Session.new(saved, 100)
      local a = { auctionID = 1, name = "A", price = 900, worth = 1420 }
      local b = { auctionID = 2, name = "B", price = 600, worth = 1000 }
      s:add(a)
      s:add(b)
      s:bought(120, a)
      s:missed(130, b, "sold to someone else")
      assert.is_nil(s:next())
      assert.same({ started = 100, spent = 900, bought = 1, worth = 1420, profit = 520 }, s:summary())
      assert.equal(900, saved.spent, "kept in the saved table")
      assert.same({ time = 130, kind = "missed", name = "B", price = 600, note = "sold to someone else" }, saved.log[1])
      assert.equal("bought", saved.log[2].kind)
      local again = Sniper.Session.new(saved, 999)
      assert.equal(100, again:summary().started, "a /reload keeps the session")
    end)

    it("keeps a find that was never sent, and lets one with no answer be found again", function()
      local s = Sniper.Session.new(nil, 100)
      local key = { itemID = 5, itemLevel = 28 }
      local a = { auctionID = 1, name = "A", price = 900, worth = 1420, itemKey = key }
      s:add(a)
      s:lookedUp(key, 900, 100)
      s:missed(110, a, "the game blocked UNKNOWN()", "unsent")
      assert.equal(a, s:next(), "still next, to buy again")
      assert.equal("unsent", s.saved.log[1].kind)
      s:missed(120, a, "no answer from the auction house", "unknown")
      assert.is_nil(s:next())
      assert.is_false(s:fresh(key, 900, 121), "its item is looked up again on the next check")
      assert.is_true(s:add({ auctionID = 1, name = "A", price = 900, worth = 1420, itemKey = key }),
        "still listed: it comes back")
    end)

    it("logs a buy that wasn't sent once per reason, and writes off a refused one", function()
      local s = Sniper.Session.new(nil, 100)
      local key = { itemID = 5 }
      local a = { auctionID = 1, name = "A", price = 900, worth = 1420, itemKey = key }
      s:add(a)
      s:missed(110, a, "busy", "unsent")
      s:missed(111, a, "busy", "unsent")
      assert.equal(1, #s.saved.log, "a second try for the same reason isn't logged again")
      s:missed(112, a, "blocked", "unsent")
      assert.equal(2, #s.saved.log)
      s:lookedUp(key, 900, 112)
      s:missed(113, a, "sold to someone else", "refused")
      assert.is_false(s:add({ auctionID = 1, name = "A", price = 900, worth = 1420, itemKey = key }),
        "a refused auction doesn't come back")
      assert.is_true(s:fresh(key, 900, 114))
    end)

    it("drops the rest of an item's finds when one is already gone, and looks the item up again", function()
      local s = Sniper.Session.new(nil, 100)
      local key, other = { itemID = 5 }, { itemID = 6 }
      local a = { auctionID = 1, name = "A", price = 900, worth = 1420, itemKey = key }
      s:add(a)
      s:add({ auctionID = 2, name = "A", price = 900, worth = 1420, itemKey = { itemID = 5 } })
      s:add({ auctionID = 3, name = "A", price = 900, worth = 1420, itemKey = key })
      s:add({ auctionID = 4, name = "B", price = 900, worth = 1000, itemKey = other })
      s:lookedUp(key, 900, 100)
      assert.equal(2, s:missed(110, a, "already gone", "gone"))
      assert.equal(1, #s.finds, "only the other item's find is left")
      assert.equal(4, s:next().auctionID)
      assert.equal("already gone. Dropped 2 more from the same search; looking again", s.saved.log[1].note)
      assert.equal(1, #s.saved.log, "one line for the lot")
      assert.is_false(s:fresh(key, 900, 111), "the item is looked up again")
      assert.is_false(s:add(a), "the gone auction doesn't come back")
      assert.is_true(s:add({ auctionID = 2, name = "A", price = 900, worth = 1420, itemKey = key }),
        "the dropped ones come back if they are still listed")
    end)

    it("logs one gone auction plainly when nothing else from its search waits", function()
      local s = Sniper.Session.new(nil, 100)
      local a = { auctionID = 1, name = "A", price = 900, worth = 1420, itemKey = { itemID = 5 } }
      s:add(a)
      assert.equal(0, s:missed(110, a, "already gone", "gone"))
      assert.equal("already gone", s.saved.log[1].note)
    end)

    it("keeps the log short", function()
      local s = Sniper.Session.new(nil, 0)
      for i = 1, Sniper.LOG_LINES + 5 do s:log(i, "passed", { name = "X" .. i }) end
      assert.equal(Sniper.LOG_LINES, #s.saved.log)
      assert.equal("X" .. (Sniper.LOG_LINES + 5), s.saved.log[1].name, "newest first")
    end)

    it("stops buying at the spend cap and above the gold to keep", function()
      local s = Sniper.Session.new({ spent = 4000 }, 0)
      assert.is_true(s:canBuy(1000, 100000, 5000, 0))
      local ok, why = s:canBuy(1001, 100000, 5000, 0)
      assert.is_false(ok)
      assert.equal("over your spend cap for this session", why)
      assert.is_true(s:canBuy(50000, 100000, 0, 0), "0: no cap")
      ok, why = s:canBuy(1000, 20500, 0, 20000)
      assert.is_false(ok)
      assert.equal("it would leave you under the gold you keep", why)
      ok, why = s:canBuy(1000, 500, 0, 0)
      assert.is_false(ok)
      assert.equal("not enough gold", why)
    end)
  end)
end)

describe("SnipeAPI", function()
  local fake = require("spec.fake_client")

  local function setup()
    local env = fake.new()
    local ns = helper.load("BetterAH/Core/Money.lua")
    helper.load("BetterAH/Game/PostingAPI.lua", ns)
    helper.load("BetterAH/Game/SnipeAPI.lua", ns)
    ns.PostingAPI.install(env, ns)
    local api = ns.SnipeAPI.install(env, ns)
    return env, api, ns
  end

  it("browses once the auction house is open and answers with the results", function()
    local env, api = setup()
    local got, why
    api:browse({ searchString = "" }, function(r, w) got, why = r, w end)
    assert.is_nil(got)
    assert.equal("the auction house is closed", why)
    env.openAuctionHouse()
    env.browseResults = { { itemKey = { itemID = 1 }, minPrice = 5 } }
    api:browse({ searchString = "" }, function(r, w) got, why = r, w end)
    env.runTimers()
    assert.equal(1, #env.browses)
    assert.equal(5, got[1].minPrice)
    assert.is_nil(why)
  end)

  it("reads every page of a browse, up to a cap", function()
    local env, api = setup()
    env.openAuctionHouse()
    env.browseResults = { { itemKey = { itemID = 1 }, minPrice = 5 } }
    env.browsePages = { { { itemKey = { itemID = 2 }, minPrice = 6 } }, { { itemKey = { itemID = 3 }, minPrice = 7 } } }
    local got
    api:browse({}, function(r) got = r end)
    env.runTimers()
    assert.equal(3, #got, "the first page and two more")
    assert.equal(3, got[3].itemKey.itemID)
    assert.equal(2, env.moreBrowses)
    env.browsePages = {}
    for i = 1, api.MAX_PAGES + 2 do env.browsePages[i] = { { itemKey = { itemID = 100 + i }, minPrice = 1 } } end
    api:browse({}, function(r) got = r end)
    env.runTimers()
    assert.equal(1 + api.MAX_PAGES, #got, "no more than MAX_PAGES extra pages")
  end)

  it("asks again for a page the client dropped", function()
    local env, api = setup()
    env.openAuctionHouse()
    env.browseResults = { { itemKey = { itemID = 1 }, minPrice = 5 } }
    local page = { { itemKey = { itemID = 2 }, minPrice = 6 } }
    env.browsePages = { page }
    local requestMore = env.C_AuctionHouse.RequestMoreBrowseResults
    local dropped = false
    env.C_AuctionHouse.RequestMoreBrowseResults = function()
      if not dropped then
        dropped = true
        env.C_Timer.After(0, function() env.fire("AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED") end)
        return
      end
      return requestMore()
    end
    local got
    api:browse({}, function(r) got = r end)
    env.runTimers()
    assert.equal(1, #env.browses, "the browse isn't sent again")
    assert.equal(2, #got)
  end)

  it("keeps the pages read when a later page never comes", function()
    local env, api = setup()
    env.openAuctionHouse()
    env.browseResults = { { itemKey = { itemID = 1 }, minPrice = 5 } }
    env.browsePages = { { { itemKey = { itemID = 2 }, minPrice = 6 } } }
    local got, why
    api:browse({}, function(r, w) got, why = r, w end)
    env.browseSilent = true
    env.runTimers(10)
    assert.equal(1, #got)
    assert.is_nil(why)
  end)

  it("waits for the throttle and gives up when nothing answers", function()
    local env, api = setup()
    env.openAuctionHouse()
    env.throttled = true
    local got, why
    api:browse({}, function(r, w) got, why = r, w end)
    assert.equal(0, #env.browses, "waits for the throttled message system")
    env.throttled = false
    env.browseSilent = true
    env.fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    assert.equal(1, #env.browses)
    env.runTimers(10)
    assert.is_nil(got)
    assert.equal("no answer from the auction house", why)
  end)

  it("buys at the buyout and reports a failed buy", function()
    local env, api, ns = setup()
    env.openAuctionHouse()
    local result, why
    api:buy(7, 900, function(ok, w) result, why = ok, w end)
    assert.is_true(ns.postingAPI.buying, "the posting adapter leaves the error event to the buy")
    env.runTimers()
    assert.is_true(result)
    assert.same({ auctionID = 7, amount = 900 }, env.bids[1])
    assert.is_nil(ns.postingAPI.buying)
    env.bidFails = true
    api:buy(8, 900, function(ok, w) result, why = ok, w end)
    env.runTimers()
    assert.is_false(result)
    assert.equal("sold to someone else, or the auction house refused", why)
  end)

  it("names the call the game blocked during a buy, and the input it came from", function()
    local env, api = setup()
    env.openAuctionHouse()
    local result, why, kind
    local placeBid = env.C_AuctionHouse.PlaceBid
    env.C_AuctionHouse.PlaceBid = function()
      env.fire("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "CastSpellByName()")
      assert.is_nil(result, "another addon's block isn't the buy's")
      env.fire("ADDON_ACTION_BLOCKED", "BetterAH", "UNKNOWN()") -- inside the call, like the client
    end
    api:buy(7, 900, function(ok, w, k) result, why, kind = ok, w, k end, "the mouse wheel")
    env.runTimers(10)
    assert.is_false(result)
    assert.equal("the game blocked UNKNOWN() from the mouse wheel", why)
    assert.equal("unsent", kind, "a blocked buy never reached the auction house")
    assert.is_nil(api.buying)
    env.C_AuctionHouse.PlaceBid = placeBid
    api:buy(8, 900, function(ok) result = ok end)
    env.runTimers()
    assert.is_true(result, "the next buy goes through")
  end)

  it("counts a blocked buy the auction house confirms after all", function()
    local env, api = setup()
    env.openAuctionHouse()
    local results = {}
    local placeBid = env.C_AuctionHouse.PlaceBid
    env.C_AuctionHouse.PlaceBid = function(...)
      placeBid(...)
      env.fire("ADDON_ACTION_BLOCKED", "BetterAH", "UNKNOWN()")
    end
    api:buy(7, 900, function(ok, _, k) results[#results + 1] = { ok, k } end)
    env.runTimers()
    assert.same({ { false, "unsent" }, { true } }, results)
  end)

  it("leaves a PlaceBid block of another addon alone", function()
    local env, api = setup()
    env.openAuctionHouse()
    local result
    api:buy(7, 900, function(ok) result = ok end)
    env.fire("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "C_AuctionHouse.PlaceBid()")
    assert.is_nil(result)
    env.runTimers()
    assert.is_true(result)
  end)

  it("hands other blocks of this addon to onBlocked", function()
    local env, api = setup()
    local got = {}
    api.onBlocked = function(event, what) got[#got + 1] = event .. " " .. what end
    env.fire("ADDON_ACTION_BLOCKED", "BetterAH", "SetPoint()")
    env.fire("ADDON_ACTION_FORBIDDEN", "SomeOtherAddon", "PickupItem()")
    assert.same({ "ADDON_ACTION_BLOCKED SetPoint()" }, got)
  end)

  it("doesn't send a buy while a query waits on the throttle", function()
    local env, api = setup()
    env.openAuctionHouse()
    env.throttled = true
    local result, why, kind
    api:buy(7, 900, function(ok, w, k) result, why, kind = ok, w, k end)
    assert.equal(0, #env.bids)
    assert.is_false(result)
    assert.equal("the auction house was still answering a check, so the buy wasn't sent", why)
    assert.equal("unsent", kind)
    assert.is_nil(api.buying)
  end)

  it("says an auction the auction house can't find is gone (#130)", function()
    local env, api = setup()
    env.openAuctionHouse()
    env.bidFails, env.bidError = true, 4
    local result, why, kind
    api:buy(7, 900, function(ok, w, k) result, why, kind = ok, w, k end)
    env.runTimers()
    assert.is_false(result)
    assert.equal("already gone (sold to someone else, or taken down)", why)
    assert.equal("gone", kind)
  end)

  it("says a buy with no answer may still be listed, and a refused one was refused", function()
    local env, api = setup()
    env.openAuctionHouse()
    local kind
    env.C_AuctionHouse.PlaceBid = function() end
    api:buy(7, 900, function(_, _, k) kind = k end)
    env.runTimers(10)
    assert.equal("unknown", kind)
  end)

  it("probes for browse and buy", function()
    local ns = helper.load("BetterAH/Core/Money.lua")
    helper.load("BetterAH/Core/SelfTest.lua", ns)
    helper.load("BetterAH/Core/Probes.lua", ns)
    helper.load("BetterAH/Game/PostingAPI.lua", ns)
    helper.load("BetterAH/Game/SnipeAPI.lua", ns)
    local env = fake.new()
    ns.PostingAPI.install(env, ns)
    ns.SnipeAPI.install(env, ns)
    local found
    for _, r in ipairs(ns.Probes.suite():run(env, ns)) do
      if r.name == "Snipe API" then found = r end
    end
    assert.same({ name = "Snipe API", status = "pass", detail = "browse and buy are available" }, found)
  end)
end)
