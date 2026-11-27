local helper = require("spec.helper")

describe("PostQueue", function()
  local ns = helper.load("BetterAH/Core/Posting.lua")
  helper.load("BetterAH/Core/PostQueue.lua", ns)
  local values = { ["i:1"] = 1000, ["i:2"] = 1000, ["i:3"] = 1000 }

  local function setup()
    local settings = ns.Posting.Settings.new({})
    settings:setProfile("i:1", 20, 2)
    settings:setProfile("i:2", 20, 2)
    local q = ns.PostQueue.new({ settings = settings, key = "/1/Horde",
      marketValue = function(item) return values[item] end })
    local need = q:setEntries({
      { item = "i:1", name = "Apple", have = 40 }, { item = "i:2", name = "Bread", have = 5 },
      { item = "i:3", name = "Cheese", have = 10 }, { item = "i:4", name = "Dates", have = 1 },
    })
    return q, settings, need
  end

  local function states(q)
    local out = {}
    for _, r in ipairs(q:rows()) do out[#out + 1] = r.item .. "=" .. r.state end
    return out
  end

  it("starts every item as checking and asks for a lookup of each", function()
    local q, _, need = setup()
    assert.equal(4, #need)
    assert.same({ "i:1=checking", "i:2=checking", "i:3=checking", "i:4=checking" }, states(q))
    assert.same({ 0, 4 }, { q:progress() })
    assert.is_nil(q:nextPost())
  end)

  it("hands each item's own auctions to the price plan (#132)", function()
    local settings = ns.Posting.Settings.new({})
    local asked
    local q = ns.PostQueue.new({ settings = settings, key = "/1/Horde", marketValue = function() return 1000 end,
      ownAuctions = function(e) asked = e.item return { { unit = 950, quantity = 20 } } end })
    q:setEntries({ { item = "i:1", name = "Apple", have = 5 } })
    q:setListings("i:1", { { unit = 950, count = 20 }, { unit = 990, count = 3 } })
    local row = q:rows()[1]
    assert.same({ "i:1", "ready", 950, 950 }, { asked, row.state, row.plan.price, row.plan.matched })
  end)

  it("counts units posted this visit as the player's until the owned list has them (#132)", function()
    local settings = ns.Posting.Settings.new({})
    local owned = { { unit = 1444, quantity = 54 } }
    local q = ns.PostQueue.new({ settings = settings, key = "/1/Horde", marketValue = function() return 1400 end,
      ownAuctions = function() return owned end })
    q:setEntries({ { item = "i:1", name = "Essence", have = 30 } })
    q:sent("i:1", 26, 1444)
    -- The search after the post sees 80 at 1444, but the owned list still says 54.
    q:setListings("i:1", { { unit = 1444, count = 80 }, { unit = 1447, count = 25 } })
    assert.same({ 1444, 1444 }, { q:rows()[1].plan.price, q:rows()[1].plan.matched })
    q:sent("i:1", -26, 1444) -- the auction house refused it after all
    assert.same({ 1443, 1444 }, { q:rows()[1].plan.price, q:rows()[1].plan.undercut })
    q:sent("i:1", 26, 1444)
    owned = { { unit = 1444, quantity = 80 } }
    q:ownedRefreshed()
    assert.same({ 1444, 1444 }, { q:rows()[1].plan.price, q:rows()[1].plan.matched }, "the owned list has them now")
  end)

  it("turns each lookup into ready, skipped or failed", function()
    local q = setup()
    q:setListings("i:1", { { unit = 990, count = 20 } })
    q:setListings("i:2", { { unit = 500, count = 20 } })
    q:setListings("i:3", {})
    q:setListings("i:4", nil, "no answer from the auction house")
    assert.same({ "i:1=ready", "i:2=skipped", "i:3=ready", "i:4=failed" }, states(q), "no profile needed")
    local rows = q:rows()
    assert.same({ "post", 989, 20, 20 },
      { rows[1].plan.action, rows[1].plan.price, rows[1].plan.quantity, rows[1].plan.remainder })
    assert.same({ 10, 0, 3 }, { rows[3].plan.quantity, rows[3].plan.remainder, rows[3].plan.duration })
    assert.equal("below-floor", rows[2].plan.reason)
    assert.equal("no answer from the auction house", rows[4].reason)
    assert.same({ 4, 4 }, { q:progress() })
    assert.equal("i:1", q:nextPost().item)
  end)

  it("uses the item's own floor on this market and the saved profile once set", function()
    local q, settings = setup()
    q:setListings("i:2", { { unit = 500, count = 20 } })
    q:setListings("i:3", {})
    settings:setFloor("/1/Horde", "i:2", 400)
    settings:setProfile("i:3", 5, 3)
    assert.same({ "i:1=checking", "i:2=ready", "i:3=ready", "i:4=checking" }, states(q))
    assert.same({ 5, 5, 3 }, { q:rows()[3].plan.quantity, q:rows()[3].plan.remainder, q:rows()[3].plan.duration })
  end)

  it("skips an item for this visit when you say so", function()
    local q = setup()
    q:setListings("i:1", { { unit = 990, count = 20 } })
    q:skip("i:1")
    local row = q:rows()[1]
    assert.same({ "skipped", "you" }, { row.state, row.skipped })
    assert.is_nil(q:nextPost())
  end)

  it("keeps what it found when the bags are read again, and looks up only new items", function()
    local q = setup()
    q:setListings("i:1", { { unit = 990, count = 20 } })
    local need = q:setEntries({ { item = "i:1", name = "Apple", have = 20 },
      { item = "i:5", name = "Eggs", have = 1 } })
    assert.same({ "i:5" }, { need[1].item })
    assert.same({ "i:1=ready", "i:5=checking" }, states(q))
    assert.equal(1, q:rows()[1].plan.posts, "the new count in the bags")
    q:forget("i:1")
    assert.equal(2, #q:setEntries({ { item = "i:1", have = 20 }, { item = "i:5", have = 1 } }))
  end)

  it("keeps what it found when one bag read misses the item (#82)", function()
    local q = setup()
    q:setListings("i:1", { { unit = 990, count = 20 } })
    q:setEntries({ { item = "i:5", name = "Eggs", have = 1 } })
    local need = q:setEntries({ { item = "i:1", name = "Apple", have = 20 },
      { item = "i:5", name = "Eggs", have = 1 } })
    assert.equal(1, #need, "Apple isn't looked up again")
    assert.equal("i:5", need[1].item)
  end)

  it("holds an item at its limit for the visit, even when the bags grow or the limit changes", function()
    local q, settings = setup()
    q:setListings("i:1", { { unit = 990, count = 20 } })
    q:sent("i:1", 20)
    q:setEntries({ { item = "i:1", name = "Apple", have = 60 } })
    local row = q:rows()[1]
    assert.same({ "skipped", "kept" }, { row.state, row.skipped }, "posted its 20, though 40 more arrived")
    settings:setProfile("i:1", 30, 2)
    assert.same({ "ready", 10 }, { q:rows()[1].state, q:rows()[1].plan.quantity }, "a raised limit posts the rest")
    settings:setProfile("i:1", "", 2)
    assert.equal(60, q:rows()[1].plan.quantity, "no limit: everything")
    q:sent("i:1", -20)
    settings:setProfile("i:1", 5, 2)
    assert.equal(5, q:rows()[1].plan.quantity, "a refused post is taken back")
  end)

  it("prices in the client's step", function()
    local settings = ns.Posting.Settings.new({ profiles = { ["i:1"] = { limit = 1, duration = 2 } } })
    local q = ns.PostQueue.new({ settings = settings,
      key = "k", marketValue = function() return 100000 end, step = 100 })
    q:setEntries({ { item = "i:1", have = 1 } })
    q:setListings("i:1", { { unit = 95050, count = 1 } })
    assert.equal(95000, q:nextPost().plan.price)
  end)

  describe("with disenchant materials", function()
    local mns = helper.load("BetterAH/Core/Disenchant.lua")
    helper.load("BetterAH/Core/MatFloors.lua", mns)
    helper.load("BetterAH/Core/Posting.lua", mns)
    helper.load("BetterAH/Core/PostQueue.lua", mns)

    local function matQueue()
      local settings = mns.Posting.Settings.new({})
      settings:setProfile("i:10940", 20, 3)
      local q = mns.PostQueue.new({ settings = settings, key = "/Normal/Horde",
        marketValue = function() return 1000 end,
        matFloor = function(item) return item == "i:10940" and { floor = 900 } or nil end })
      q:setEntries({ { item = "i:2589", name = "Linen Cloth", have = 20 },
        { item = "i:10940", name = "Strange Dust", have = 40 } })
      return q, settings
    end

    it("shows only the materials with the mats filter, and looks up only those", function()
      local q = matQueue()
      local need = q:setFilter("mats")
      assert.equal(1, #need)
      assert.equal("i:10940", need[1].item)
      assert.equal(1, #q:rows())
      assert.same({ 1, 2 }, { q:counts() })
      local done, total = q:progress()
      assert.same({ 0, 1 }, { done, total })
      q:setListings("i:10940", { { unit = 950, count = 20 } })
      assert.equal("i:10940", q:nextPost().item)
      assert.equal(1, #q:setFilter("all"), "linen still needs its lookup")
      assert.equal(2, #q:rows())
    end)

    it("uses the rule's floor for a material without its own", function()
      local q, settings = matQueue()
      q:setListings("i:10940", { { unit = 880, count = 20 } })
      local row = q:rows()[2]
      assert.equal("below-floor", row.plan.reason)
      assert.equal(900, row.plan.floor)
      settings:setFloor("/Normal/Horde", "i:10940", 500)
      row = q:rows()[2]
      assert.equal("ready", row.state, "your own floor wins")
      assert.equal(500, row.own)
    end)
  end)

  describe("with essences (#234)", function()
    local ens = helper.load("BetterAH/Core/Disenchant.lua")
    helper.load("BetterAH/Core/MatFloors.lua", ens)
    helper.load("BetterAH/Core/EssenceSwap.lua", ens)
    helper.load("BetterAH/Core/Posting.lua", ens)
    helper.load("BetterAH/Core/PostQueue.lua", ens)
    local LESSER, GREATER = "i:11174", "i:11175"
    local mv = { [LESSER] = 3885, [GREATER] = 11960 }

    local function essenceQueue(entries, floors)
      local asked = {}
      local q = ens.PostQueue.new({ settings = ens.Posting.Settings.new({}), key = "/Normal/Horde",
        marketValue = function(item) return mv[item] end,
        matFloor = function(item) return floors and floors[item] and { floor = floors[item] } or nil end,
        ownAuctions = function(e) asked[#asked + 1] = e.item return nil end })
      q:setEntries(entries or { { item = LESSER, name = "Lesser Nether Essence", have = 20, commodity = true } })
      return q, asked
    end

    it("asks for the other form of each essence it shows, once found or being found", function()
      local q = essenceQueue({ { item = LESSER, name = "Lesser Nether Essence", have = 20, commodity = true },
        { item = "i:10940", name = "Strange Dust", have = 5, commodity = true } })
      assert.same({ GREATER }, q:counterparts())
      q:setListings(GREATER, { { unit = 11960, count = 50 } })
      assert.same({}, q:counterparts())
      q:setListings(GREATER, nil, "no answer")
      assert.same({ GREATER }, q:counterparts(), "a failed lookup is tried again")
    end)

    it("doesn't ask for the other form with too few to combine", function()
      local q = essenceQueue({ { item = LESSER, name = "Lesser Nether Essence", have = 2, commodity = true } })
      assert.same({}, q:counterparts())
    end)

    it("says why the other form wouldn't post", function()
      local q = essenceQueue()
      mv[GREATER] = nil
      q:setListings(LESSER, { { unit = 3884, count = 100 } })
      q:setListings(GREATER, {})
      local s = q:rows()[1].swap
      mv[GREATER] = 11960
      assert.is_nil(s, "no price for the greater at all")
      q:setListings(GREATER, { { unit = 11960, count = 1 } })
      mv[GREATER] = nil
      s = q:rows()[1].swap
      mv[GREATER] = 11960
      assert.is_false(s.otherPosts)
      assert.equal("no-floor", s.otherReason)
    end)

    it("doesn't ask for the other form when it is in the bags too", function()
      local q = essenceQueue({ { item = LESSER, name = "Lesser Nether Essence", have = 20, commodity = true },
        { item = GREATER, name = "Greater Nether Essence", have = 4, commodity = true } })
      assert.same({}, q:counterparts())
    end)

    it("compares posting as is with combining, at the price the other form would post at", function()
      local q, asked = essenceQueue()
      q:setListings(LESSER, { { unit = 3884, count = 100 } })
      assert.is_nil(q:rows()[1].swap, "nothing to compare until the greater is looked up")
      q:setListings(GREATER, { { unit = 11960, count = 50 } })
      local row = q:rows()[1]
      assert.equal(3883, row.plan.price)
      local s = row.swap
      assert.equal("combine", s.direction)
      assert.equal(11959, s.otherPrice)
      assert.equal(6, s.units)
      assert.equal(math.floor((6 * 11959 + 2 * 3883) * 0.95) - math.floor(20 * 3883 * 0.95), s.gain)
      assert.is_true(s.better)
      assert.truthy(table.concat(asked, ","):find(GREATER, 1, true), "the greater's own auctions count")
    end)

    it("doesn't advise converting when the other form would go below its floor", function()
      local q = essenceQueue(nil, { [GREATER] = 12500 })
      q:setListings(LESSER, { { unit = 3884, count = 100 } })
      q:setListings(GREATER, { { unit = 11960, count = 50 } })
      local s = q:rows()[1].swap
      assert.is_true(s.gain > 0)
      assert.is_false(s.better)
    end)

    it("uses the other form's bag entry and listings when it is in the bags", function()
      local q = essenceQueue({ { item = LESSER, name = "Lesser Nether Essence", have = 20, commodity = true },
        { item = GREATER, name = "Greater Nether Essence", have = 4, commodity = true } })
      q:setListings(LESSER, { { unit = 3884, count = 100 } })
      q:setListings(GREATER, { { unit = 11960, count = 50 } })
      local rows = q:rows()
      assert.is_true(rows[1].swap.better)
      assert.equal("split", rows[2].swap.direction)
      assert.is_false(rows[2].swap.better)
    end)

    it("leaves other items without a comparison", function()
      local q = essenceQueue({ { item = "i:10940", name = "Strange Dust", have = 5, commodity = true } })
      q:setListings("i:10940", { { unit = 900, count = 20 } })
      assert.is_nil(q:rows()[1].swap)
    end)
  end)
end)
