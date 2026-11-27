local helper = require("spec.helper")

describe("EssenceSwap", function()
  local ns = helper.load("BetterAH/Core/Disenchant.lua")
  helper.load("BetterAH/Core/EssenceSwap.lua", ns)
  local S = ns.EssenceSwap
  local LESSER, GREATER = "i:11174", "i:11175" -- Nether

  it("knows each essence's other form", function()
    assert.same({ GREATER, "combine" }, { S.counterpart(LESSER) })
    assert.same({ LESSER, "split" }, { S.counterpart(GREATER) })
    assert.same({ "i:10939", "combine" }, { S.counterpart("i:10938") })
    assert.same({ "i:16202", "split" }, { S.counterpart("i:16203") })
  end)

  it("has no other form for dust, shards, crystals or other items", function()
    assert.is_nil(S.counterpart("i:10940")) -- Strange Dust
    assert.is_nil(S.counterpart("i:11178")) -- Large Radiant Shard
    assert.is_nil(S.counterpart("i:20725")) -- Nexus Crystal
    assert.is_nil(S.counterpart("i:2589"))
    assert.is_nil(S.counterpart(nil))
  end)

  it("combines lessers in threes and keeps the rest", function()
    assert.same({ 6, 2 }, { S.converted("combine", 20) })
    assert.same({ 1, 0 }, { S.converted("combine", 3) })
    assert.same({ 0, 2 }, { S.converted("combine", 2) })
  end)

  it("splits each greater into three lessers", function()
    assert.same({ 12, 0 }, { S.converted("split", 4) })
  end)

  it("advises combining when the greater sells for more than three lessers", function()
    -- The mockup's numbers: 20 lesser at 38s 83c, greater at 1g 19s 59c.
    local c = S.compare({ item = LESSER, have = 20, price = 3883, otherPrice = 11959, otherPosts = true })
    assert.equal("combine", c.direction)
    assert.equal(GREATER, c.other)
    assert.equal("Greater Nether Essence", c.otherName)
    assert.equal(6, c.units)
    assert.equal(2, c.left)
    assert.equal(math.floor(20 * 3883 * 0.95), c.asIs)
    assert.equal(math.floor((6 * 11959 + 2 * 3883) * 0.95), c.convert)
    assert.equal(c.convert - c.asIs, c.gain)
    assert.is_true(c.better)
  end)

  it("compares a split that earns less without advising it", function()
    local c = S.compare({ item = GREATER, have = 4, price = 11959, otherPrice = 3883, otherPosts = true })
    assert.equal("split", c.direction)
    assert.equal(12, c.units)
    assert.equal(0, c.left)
    assert.is_true(c.gain < 0)
    assert.is_false(c.better)
  end)

  it("advises a split when three lessers sell for more", function()
    local c = S.compare({ item = GREATER, have = 2, price = 9000, otherPrice = 4000, otherPosts = true })
    assert.is_true(c.better)
    assert.equal(math.floor(6 * 4000 * 0.95) - math.floor(2 * 9000 * 0.95), c.gain)
  end)

  it("doesn't advise a gain under 1%", function()
    -- 30 lesser at 1000 each, 10 greater at 3020: 0.67% more.
    local c = S.compare({ item = LESSER, have = 30, price = 1000, otherPrice = 3020, otherPosts = true })
    assert.is_true(c.gain > 0)
    assert.is_false(c.better)
    c = S.compare({ item = LESSER, have = 30, price = 1000, otherPrice = 3030, otherPosts = true })
    assert.is_true(c.better)
  end)

  it("doesn't advise converting when the converted post wouldn't go up", function()
    local c = S.compare({ item = LESSER, have = 20, price = 3883, otherPrice = 11959, otherPosts = false })
    assert.is_true(c.gain > 0)
    assert.is_false(c.better)
  end)

  it("has nothing to compare without both prices, enough to combine, or an essence", function()
    assert.is_nil(S.compare({ item = LESSER, have = 20, price = nil, otherPrice = 11959, otherPosts = true }))
    assert.is_nil(S.compare({ item = LESSER, have = 20, price = 3883, otherPrice = nil, otherPosts = true }))
    assert.is_nil(S.compare({ item = LESSER, have = 2, price = 3883, otherPrice = 11959, otherPosts = true }))
    assert.is_nil(S.compare({ item = LESSER, have = 0, price = 3883, otherPrice = 11959, otherPosts = true }))
    assert.is_nil(S.compare({ item = "i:10940", have = 20, price = 100, otherPrice = 300, otherPosts = true }))
  end)
end)
