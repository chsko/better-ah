local helper = require("spec.helper")

describe("Posting", function()
  local Posting = helper.load("BetterAH/Core/Posting.lua").Posting
  local profile = { duration = 2 }

  local function plan(args)
    if args.profile == false then args.profile = nil else args.profile = args.profile or profile end
    return Posting.plan(args)
  end

  it("undercuts the cheapest competing listing by 1 copper", function()
    local p = plan({ have = 60, marketValue = 1000, listings = {
      { unit = 1200, count = 20 }, { unit = 950, count = 5 }, { unit = 990, count = 20 },
    } })
    assert.same({ action = "post", price = 949, floor = 800, undercut = 950, duration = 2,
      quantity = 60, posts = 1, remainder = 0 }, p)
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

  it("posts everything for 24 hours without a profile", function()
    local p = plan({ have = 142, marketValue = 1000, commodity = true, maxStack = 20, profile = false,
      listings = { { unit = 1000, count = 20 } } })
    assert.same({ action = "post", price = 999, floor = 800, undercut = 1000, duration = 3,
      quantity = 142, posts = 1, remainder = 0 }, p, "a commodity is one post of any size, past one bag stack")
    assert.equal("skip", plan({ have = 50, profile = false, listings = {} }).action, "still needs a floor")
  end)

  it("posts for the player's default duration when the profile has none", function()
    local base = { have = 5, marketValue = 100, commodity = true, listings = {}, profile = false }
    base.defaultDuration = 1
    assert.equal(1, plan(base).duration, "no profile")
    base.profile = { limit = 2 }
    assert.equal(1, plan(base).duration, "a profile without a duration")
    base.profile = { duration = 2 }
    assert.equal(2, plan(base).duration, "the profile's own duration wins")
    base.profile, base.defaultDuration = false, 7
    assert.equal(3, plan(base).duration, "a duration the client doesn't offer falls back to 24 hours")
  end)

  it("posts at most the profile's limit and keeps the rest in the bags", function()
    local p = plan({ have = 142, marketValue = 100, commodity = true, profile = { limit = 50, duration = 1 },
      listings = {} })
    assert.same({ 50, 1, 92, 50, 1 }, { p.quantity, p.posts, p.remainder, p.limit, p.duration })
    local few = plan({ have = 7, marketValue = 100, commodity = true, profile = { limit = 50 }, listings = {} })
    assert.same({ 7, 1, 0, 3 }, { few.quantity, few.posts, few.remainder, few.duration },
      "fewer than the limit: all of them, and 24 hours by default")
  end)

  it("posts other items one auction per bag stack", function()
    local gear = plan({ have = 3, marketValue = 100, maxStack = 1, listings = {} })
    assert.same({ 1, 3, 0 }, { gear.quantity, gear.posts, gear.remainder })
    local limited = plan({ have = 5, marketValue = 100, maxStack = 1, profile = { limit = 2 }, listings = {} })
    assert.same({ 1, 2, 3 }, { limited.quantity, limited.posts, limited.remainder })
    local stacks = plan({ have = 50, marketValue = 100, maxStack = 20, listings = {} })
    assert.same({ 20, 3, 0 }, { stacks.quantity, stacks.posts, stacks.remainder }, "the last stack may be smaller")
  end)

  it("counts what this visit already posted toward the limit", function()
    local p = plan({ have = 30, marketValue = 100, commodity = true, posted = 20, profile = { limit = 30 },
      listings = {} })
    assert.same({ 10, 1, 20 }, { p.quantity, p.posts, p.remainder }, "only the 10 still due from the limit")
    local grown = plan({ have = 132, marketValue = 100, commodity = true, posted = 50, profile = { limit = 50 },
      listings = {} })
    assert.same({ action = "skip", reason = "limit", limit = 50 }, grown, "more in the bags doesn't reset it")
    assert.equal(132, plan({ have = 132, marketValue = 100, commodity = true, posted = 50, listings = {} }).quantity,
      "without a limit everything posts")
  end)

  it("posts a non-commodity one bag stack per auction", function()
    local p = plan({ have = 20, marketValue = 100, maxStack = 20, stacks = { 5, 5, 5, 5 }, listings = {} })
    assert.same({ 5, 4, 0 }, { p.quantity, p.posts, p.remainder })
    local cut = plan({ have = 20, marketValue = 100, stacks = { 5, 5, 5, 5 }, profile = { limit = 12 },
      listings = {} })
    assert.same({ 5, 3, 8 }, { cut.quantity, cut.posts, cut.remainder }, "the last auction cut to the limit")
    local small = plan({ have = 20, marketValue = 100, stacks = { 5, 15 }, profile = { limit = 3 }, listings = {} })
    assert.same({ 3, 1 }, { small.quantity, small.posts })
  end)

  it("ignores a broken or old saved profile", function()
    for _, bad in ipairs({ { stack = 20, duration = 2 }, { limit = "x", duration = 9 }, { limit = 0.5 }, {} }) do
      local p = plan({ have = 40, marketValue = 1, commodity = true, profile = bad, listings = {} })
      assert.same({ "post", 40 }, { p.action, p.quantity })
    end
    assert.equal(2, plan({ have = 1, marketValue = 1, profile = { stack = 20, duration = 2 }, listings = {} })
      .duration, "an old profile keeps its duration")
  end)

  it("prices in whole silver on a client without copper values", function()
    local p = plan({ have = 20, marketValue = 100000, step = 100, listings = { { unit = 95050, count = 1 } } })
    assert.same({ "post", 95000 }, { p.action, p.price })
    local even = plan({ have = 20, marketValue = 100000, step = 100, listings = { { unit = 95000, count = 1 } } })
    assert.equal(94900, even.price, "a whole silver below an even price")
    assert.equal("skip", plan({ have = 20, marketValue = 1000, step = 100, listings = { { unit = 790, count = 1 } } })
      .action, "7s, the silver below 7s 90c, is under the 8s floor")
    assert.equal(1100, plan({ have = 20, marketValue = 1000, floor = 1050, step = 100, listings = {} }).price,
      "no competition: the floor rounded up to silver")
  end)

  it("never posts for 0 copper and skips when nothing is left", function()
    assert.equal(1, plan({ have = 1, floor = 1, listings = { { unit = 1, count = 1 } } }).price)
    assert.same({ action = "skip", reason = "none-left" }, plan({ have = 0, listings = {} }))
  end)

  it("rounds the default floor up and an own floor down to whole copper", function()
    assert.equal(8, Posting.floor(9))
    assert.equal(3, Posting.floor(3, 3.7))
    assert.is_nil(Posting.floor(nil, 0))
    assert.equal(5, Posting.floor(9, nil, 4.2), "a rule's floor beats the default share")
    assert.equal(3, Posting.floor(9, 3, 5), "and your own floor beats the rule")
  end)

  describe("Settings", function()
    it("remembers posting profiles, and floor prices per market, across a reload", function()
      local store = {}
      local s = Posting.Settings.new(store)
      assert.is_true(s:setProfile("i:2589", 20, 3))
      assert.is_true(s:setFloor("/1/Horde", "i:2589", 1234.9))
      s = Posting.Settings.new(store)
      assert.same({ limit = 20, duration = 3 }, s:profile("i:2589"))
      assert.is_true(s:setProfile("i:2589", " ", 1))
      assert.same({ duration = 1 }, s:profile("i:2589"), "an empty limit posts everything")
      assert.equal(1234, s:floor("/1/Horde", "i:2589"))
      assert.is_nil(s:floor("/1/Alliance", "i:2589"), "a floor is a price on one market")
      assert.is_true(s:setFloor("/1/Horde", "i:2589", 0))
      assert.is_nil(s:floor("/1/Horde", "i:2589"), "0 goes back to the default floor")
    end)

    it("remembers the default duration across a reload, and refuses one the client doesn't offer", function()
      local store = {}
      local s = Posting.Settings.new(store)
      assert.equal(3, s:defaultDuration(), "24 hours until the player picks another")
      assert.is_true(s:setDefaultDuration(2))
      s = Posting.Settings.new(store)
      assert.equal(2, s:defaultDuration())
      for _, bad in ipairs({ 0, 4, "abc", 2.5, false }) do
        assert.is_false(s:setDefaultDuration(bad), tostring(bad))
      end
      assert.equal(2, s:defaultDuration())
      store.duration = 9
      assert.equal(3, s:defaultDuration(), "a bad saved value reads as 24 hours")
    end)

    it("gives an item its profile's duration, else the default", function()
      local s = Posting.Settings.new({})
      assert.is_true(s:setDefaultDuration(1))
      assert.equal(1, s:durationFor("i:1"))
      s:setProfile("i:1", "", 3)
      assert.equal(3, s:durationFor("i:1"))
      assert.is_true(s:setProfile("i:2", 5, nil))
      assert.equal(1, s:durationFor("i:2"), "a profile saved without a duration")
    end)

    it("moves floors from an old market key to a new one that has none", function()
      local store = { floors = { ["/1/Horde"] = { ["i:1"] = 500 }, ["/PvP/Horde"] = { ["i:2"] = 7 } } }
      local s = Posting.Settings.new(store)
      assert.is_true(s:adoptFloors("/1/Horde", "/Normal/Horde"))
      assert.equal(500, s:floor("/Normal/Horde", "i:1"))
      assert.is_nil(s:floor("/1/Horde", "i:1"))
      assert.is_false(s:adoptFloors("/Normal/Horde", "/PvP/Horde"), "never over floors already set")
      assert.equal(500, s:floor("/Normal/Horde", "i:1"))
      assert.is_false(s:adoptFloors("/1/Alliance", "/PvP/Alliance"), "nothing to move")
    end)

    it("refuses bad limits, unknown durations and floors that aren't a copper amount", function()
      local s = Posting.Settings.new({})
      assert.is_false(s:setProfile("i:1", 0, 2))
      assert.is_false(s:setProfile("i:1", "2.5", 2))
      assert.is_false(s:setProfile("i:1", "abc", 2))
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
