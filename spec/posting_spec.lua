local helper = require("spec.helper")

describe("Posting", function()
  local Posting = helper.load("BetterAH/Core/Posting.lua").Posting
  local profile = { stack = 20, duration = 2 }

  local function plan(args)
    if args.profile == false then args.profile = nil else args.profile = args.profile or profile end
    return Posting.plan(args)
  end

  it("undercuts the cheapest competing listing by 1 copper", function()
    local p = plan({ have = 60, marketValue = 1000, listings = {
      { unit = 1200, count = 20 }, { unit = 950, count = 5 }, { unit = 990, count = 20 },
    } })
    assert.same({ action = "post", price = 949, floor = 800, undercut = 950, duration = 2,
      quantity = 20, posts = 3, remainder = 0 }, p)
  end)

  it("goes just under a fractional unit price, not a copper further", function()
    local p = plan({ have = 20, marketValue = 1000, listings = { { unit = 800.5, count = 2 } } })
    assert.same({ "post", 800, 800.5 }, { p.action, p.price, p.undercut })
    assert.equal(950, plan({ have = 20, marketValue = 1000, listings = { { unit = 950.5, count = 2 } } }).price)
  end)

  it("ignores the player's own listings, but not other sellers' units in a shared row", function()
    local p = plan({ have = 20, marketValue = 1000, listings = {
      { unit = 900, count = 20, ownCount = 20 }, { unit = 980, count = 20 },
    } })
    assert.same({ 979, 980 }, { p.price, p.undercut })
    local shared = plan({ have = 20, marketValue = 1000, listings = { { unit = 900, count = 30, ownCount = 20 } } })
    assert.equal(899, shared.price)
  end)

  it("prices at market value when nobody else is selling", function()
    local p = plan({ have = 20, marketValue = 1000, listings = { { unit = 700, count = 20, ownCount = 20 } } })
    assert.same({ 1000, nil }, { p.price, p.undercut })
    assert.equal(1500, (plan({ have = 20, marketValue = 1000, floor = 1500, listings = {} })).price,
      "but never below the item's own floor")
  end)

  it("skips an item when the undercut would go below the floor price, and says why", function()
    local p = plan({ have = 20, marketValue = 1000, listings = { { unit = 700, count = 20 } } })
    assert.same({ action = "skip", reason = "below-floor", price = 699, floor = 800 }, p)
    assert.equal("post", plan({ have = 20, marketValue = 1000, listings = { { unit = 801, count = 1 } } }).action,
      "exactly at the floor still posts")
    local own = plan({ have = 20, marketValue = 1000, floor = 500, listings = { { unit = 700, count = 20 } } })
    assert.same({ "post", 699, 500 }, { own.action, own.price, own.floor }, "the item's own floor wins")
  end)

  it("skips an item with no market value and no floor of its own", function()
    local p = plan({ have = 20, listings = { { unit = 700, count = 20 } } })
    assert.same({ action = "skip", reason = "no-floor", price = 699 }, p)
    assert.equal("post", plan({ have = 20, floor = 600, listings = { { unit = 700, count = 20 } } }).action)
  end)

  it("asks for a posting profile only for items that would post", function()
    local listings = {
      { unit = 1000, count = 5 }, { unit = 1000, count = 20 }, { unit = 1000, count = 20 }, { unit = 1000, count = 10 },
      { unit = 1000, count = 10 }, { unit = 1000, count = 1, ownCount = 1 }, { unit = 1000, count = 1, ownCount = 1 },
      { unit = 1000, count = 1, ownCount = 1 },
    }
    local p = plan({ have = 50, marketValue = 1000, profile = false, listings = listings })
    assert.same({ action = "profile", price = 999, floor = 800, suggested = { stack = 20, duration = 2 } }, p,
      "the most common competing stack (ties go to the bigger) and 24 hours")
    assert.equal("skip", plan({ have = 50, profile = false, listings = listings }).action)
    assert.same({ stack = 7, duration = 2 },
      plan({ have = 7, marketValue = 1, profile = false, listings = {} }).suggested, "no competitors: all you have")
    assert.equal(10, plan({ have = 50, marketValue = 1, maxStack = 10, profile = false, listings = {} })
      .suggested.stack, "never more than a stack holds")
  end)

  it("posts whole stacks and keeps the rest in the bags", function()
    local p = plan({ have = 50, marketValue = 100, listings = {} })
    assert.same({ 20, 2, 10 }, { p.quantity, p.posts, p.remainder })
    local few = plan({ have = 7, marketValue = 100, listings = {} })
    assert.same({ 7, 1, 0 }, { few.quantity, few.posts, few.remainder }, "fewer than a stack: one smaller stack")
    local capped = plan({ have = 50, marketValue = 100, maxStack = 10, listings = {} })
    assert.same({ 10, 5 }, { capped.quantity, capped.posts })
  end)

  it("treats a broken saved profile as no profile", function()
    for _, bad in ipairs({ { stack = "x", duration = 2 }, { stack = 0.5, duration = 2 }, { stack = 20 } }) do
      assert.equal("profile", plan({ have = 5, marketValue = 1, profile = bad, listings = {} }).action)
    end
  end)

  it("never posts for 0 copper and skips when nothing is left", function()
    assert.equal(1, plan({ have = 1, floor = 1, listings = { { unit = 1, count = 1 } } }).price)
    assert.same({ action = "skip", reason = "none-left" }, plan({ have = 0, listings = {} }))
  end)

  it("rounds the default floor up and an own floor down to whole copper", function()
    assert.equal(8, Posting.floor(9))
    assert.equal(3, Posting.floor(3, 3.7))
    assert.is_nil(Posting.floor(nil, 0))
  end)

  describe("Settings", function()
    it("remembers posting profiles, and floor prices per market, across a reload", function()
      local store = {}
      local s = Posting.Settings.new(store)
      assert.is_true(s:setProfile("i:2589", 20, 3))
      assert.is_true(s:setFloor("/1/Horde", "i:2589", 1234.9))
      s = Posting.Settings.new(store)
      assert.same({ stack = 20, duration = 3 }, s:profile("i:2589"))
      assert.equal(1234, s:floor("/1/Horde", "i:2589"))
      assert.is_nil(s:floor("/1/Alliance", "i:2589"), "a floor is a price on one market")
      assert.is_true(s:setFloor("/1/Horde", "i:2589", 0))
      assert.is_nil(s:floor("/1/Horde", "i:2589"), "0 goes back to the default floor")
    end)

    it("refuses bad stacks, unknown durations and floors that aren't a copper amount", function()
      local s = Posting.Settings.new({})
      assert.is_false(s:setProfile("i:1", 0, 2))
      assert.is_false(s:setProfile("i:1", 5, 4))
      assert.is_false(s:setProfile("i:1", math.huge, 2))
      assert.is_nil(s:profile("i:1"))
      assert.is_true(s:setFloor("k", "i:1", 500))
      for _, bad in ipairs({ -1, 0.5, "12g", "abc", math.huge, 0 / 0 }) do
        assert.is_false(s:setFloor("k", "i:1", bad), tostring(bad))
      end
      assert.equal(500, s:floor("k", "i:1"), "a typo keeps the floor")
    end)
  end)
end)
