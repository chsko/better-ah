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

  it("turns each lookup into ready, setup, skipped or failed", function()
    local q = setup()
    q:setListings("i:1", { { unit = 990, count = 20 } })
    q:setListings("i:2", { { unit = 500, count = 20 } })
    q:setListings("i:3", {})
    q:setListings("i:4", nil, "no answer from the auction house")
    assert.same({ "i:1=ready", "i:2=skipped", "i:3=setup", "i:4=failed" }, states(q))
    local rows = q:rows()
    assert.same({ "post", 989, 2 }, { rows[1].plan.action, rows[1].plan.price, rows[1].plan.posts })
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
    assert.same({ 5, 2, 3 }, { q:rows()[3].plan.quantity, q:rows()[3].plan.posts, q:rows()[3].plan.duration })
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

  it("prices in the client's step", function()
    local settings = ns.Posting.Settings.new({ profiles = { ["i:1"] = { stack = 1, duration = 2 } } })
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
end)
