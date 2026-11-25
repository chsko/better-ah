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
