local helper = require("spec.helper")

describe("Purchases", function()
  local Purchases = helper.load("BetterAH/Core/Purchases.lua").Purchases

  it("reads the item ID and suffix from a link or item string", function()
    assert.same({ 4251, -34 },
      { Purchases.parseLink("|cff1eff00|Hitem:4251:0:0:0:0:0:-34:123456:20|h[Hillman's Shoulders]|h|r") })
    assert.same({ 10940 }, { Purchases.parseLink("|Hitem:10940::::::::60:::::|h[Strange Dust]|h") })
    assert.same({ 4251, 812 }, { Purchases.parseLink("item:4251::::::812") })
    assert.is_nil(Purchases.parseLink("|Hspell:133|h[Fireball]|h"))
    assert.is_nil(Purchases.parseLink(nil))
  end)

  it("gives the price paid, averaged over every buy", function()
    local p = Purchases.new({})
    assert.is_nil(p:paid("i:10940"))
    p:bought(10940, nil, 10, 1500, 1)
    p:bought(10940, nil, 2, 600, 2)
    assert.same({ unit = 175, units = 12 }, p:paid("i:10940", nil, 12))
  end)

  it("keeps a green's suffix apart: each suffix has its own price", function()
    local p = Purchases.new({})
    p:bought(4251, "item:4251:0:0:0:0:0:-34", 1, 21000, 1)
    p:bought(4251, "item:4251:0:0:0:0:0:-12", 1, 9000, 2)
    assert.same({ unit = 21000, units = 1 }, p:paid("i:4251", -34))
    assert.same({ unit = 9000, units = 1 }, p:paid("i:4251", -12))
    assert.is_nil(p:paid("i:4251", -7), "a suffix never bought has no price")
    assert.same({ unit = 15000, units = 2 }, p:paid("i:4251", nil, 2))
  end)

  it("refuses a buy of nothing", function()
    local p = Purchases.new({})
    assert.is_false(p:bought(10940, nil, 0, 100, 1))
    assert.is_false(p:bought(nil, nil, 1, 100, 1))
    assert.is_nil(p:paid("i:10940"))
  end)

  it("prices only as many units as are held, newest buys first", function()
    local p = Purchases.new({})
    p:bought(10940, nil, 10, 1000, 1) -- 1s each
    p:bought(10940, nil, 10, 3000, 2) -- 3s each
    assert.same({ unit = 200, units = 20 }, p:paid("i:10940", nil, 34), "never more than was bought")
    assert.same({ unit = 233, units = 15 }, p:paid("i:10940", nil, 15))
    assert.same({ unit = 300, units = 10 }, p:paid("i:10940", nil, 10))
    assert.same({ unit = 300, units = 1 }, p:paid("i:10940", nil, 0), "one, for an item not in the bags")
  end)

  it("keeps a price while the item is away: in the mail, on an alt or in an auction", function()
    local p = Purchases.new({})
    p:bought(4251, "item:4251:0:0:0:0:0:-34", 1, 21000, 1)
    assert.same({ unit = 21000, units = 1 }, p:paid("i:4251", -34, 1))
  end)

  it("forgets buys older than MAX_DAYS", function()
    local p = Purchases.new({})
    local day = 86400
    p:bought(10940, nil, 5, 500, 0)
    p:bought(10940, nil, 5, 1500, 30 * day)
    p:prune((Purchases.MAX_DAYS + 10) * day)
    assert.same({ unit = 300, units = 5 }, p:paid("i:10940", nil, 10))
    p:prune((Purchases.MAX_DAYS + 40) * day)
    assert.is_nil(p:paid("i:10940"))
  end)

  it("keeps at most MAX_LOTS buys of an item", function()
    local p = Purchases.new({})
    for i = 1, Purchases.MAX_LOTS + 5 do p:bought(10940, nil, 1, i, i) end
    assert.equal(Purchases.MAX_LOTS, p:paid("i:10940", nil, 1000).units)
  end)
end)
