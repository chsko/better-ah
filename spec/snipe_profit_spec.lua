local helper = require("spec.helper")

describe("SnipeProfit", function()
  local ns = helper.load("BetterAH/Core/Purchases.lua")
  local SnipeProfit = helper.load("BetterAH/Core/SnipeProfit.lua", ns).SnipeProfit
  local armor = { name = "Armor", min = 21, max = 25, profit = "2g", worth = 12000 }

  it("stamps a sniped green with its target, band and price", function()
    local sp = SnipeProfit.new({})
    assert.is_true(sp:bought(4251, "item:4251:0:0:0:0:0:-34", 8500, 100, armor))
    local g = sp.store.greens[1]
    assert.same({ t = 100, item = 4251, s = -34, c = 8500,
      target = { name = "Armor", min = 21, max = 25, profit = "2g", worth = 12000 } }, g)
  end)

  it("keeps its own copy of the target, so editing the target later doesn't move the green", function()
    local sp = SnipeProfit.new({})
    local target = { name = "Armor", min = 21, max = 25 }
    sp:bought(4251, nil, 8500, 100, target)
    target.name, target.min = "Weapons", 26
    assert.same("Armor", sp.store.greens[1].target.name)
    assert.same(21, sp.store.greens[1].target.min)
  end)

  it("refuses a buy with no item or no price", function()
    local sp = SnipeProfit.new({})
    assert.is_false(sp:bought(nil, nil, 100, 1, armor))
    assert.is_false(sp:bought(4251, nil, 0, 1, armor))
    assert.same({}, sp.store.greens)
  end)

  it("gives a disenchant's mats to the oldest green of that item and suffix not yet disenchanted", function()
    local sp = SnipeProfit.new({})
    sp:bought(4251, "item:4251:0:0:0:0:0:-34", 8000, 100, armor)
    sp:bought(4251, "item:4251:0:0:0:0:0:-12", 7000, 110, armor)
    sp:bought(4251, "item:4251:0:0:0:0:0:-12", 7500, 120, armor)
    local g = sp:disenchanted(4251, -12, "Regrin-Forever", 200, { [10940] = 3 })
    assert.equal(sp.store.greens[2], g)
    assert.same({ t = 200, char = "Regrin-Forever", mats = { [10940] = 3 } }, g.de)
    local g2 = sp:disenchanted(4251, -12, "Regrin-Forever", 210, { [10940] = 2 })
    assert.equal(sp.store.greens[3], g2)
  end)

  it("pairs a disenchant and a green when either suffix is unknown", function()
    local sp = SnipeProfit.new({})
    sp:bought(4251, "item:4251:0:0:0:0:0:-34", 8000, 100, armor)
    sp:bought(4251, nil, 7000, 110, armor)
    local g = sp:disenchanted(4251, -12, "Alt-Forever", 200, { [10940] = 4 })
    assert.equal(sp.store.greens[2], g, "a green bought without a suffix takes any")
    local g2 = sp:disenchanted(4251, nil, "Alt-Forever", 210, { [10940] = 4 })
    assert.equal(sp.store.greens[1], g2, "no suffix known: the oldest green of the item")
    local g3 = sp:disenchanted(4251, -34, "Alt-Forever", 220, { [10940] = 4 })
    assert.is_nil(g3.target, "both sniped greens are used up, so this one was not sniped")
  end)

  it("never gives a disenchant to a green of another known suffix", function()
    local sp = SnipeProfit.new({})
    sp:bought(4251, "item:4251:0:0:0:0:0:-34", 8000, 100, armor)
    local g = sp:disenchanted(4251, -12, "Alt-Forever", 200, { [10940] = 4 }, 3000)
    assert.is_nil(g.target, "the -34 green is another item, still waiting")
    assert.equal(3000, g.c)
    assert.is_nil(sp.store.greens[1].de)
  end)

  it("adds a disenchant no sniped green matches as Not sniped, at the price the caller knows", function()
    local sp = SnipeProfit.new({})
    local g = sp:disenchanted(9999, nil, "Alt-Forever", 200, { [10940] = 2 }, 4200)
    assert.same({ t = 200, item = 9999, c = 4200,
      de = { t = 200, char = "Alt-Forever", mats = { [10940] = 2 } } }, g)
    local g2 = sp:disenchanted(9998, nil, "Alt-Forever", 210, { [10940] = 1 })
    assert.equal(0, g2.c, "no known price counts as nothing spent")
  end)

  it("drops mats with no count and refuses a disenchant with none", function()
    local sp = SnipeProfit.new({})
    assert.is_nil(sp:disenchanted(4251, nil, "A", 200, {}))
    assert.is_nil(sp:disenchanted(4251, nil, "A", 200, { [10940] = 0 }))
    assert.is_nil(sp:disenchanted(nil, nil, "A", 200, { [10940] = 1 }))
    local g = sp:disenchanted(4251, nil, "A", 200, { [10940] = 2, [10938] = 0 })
    assert.same({ [10940] = 2 }, g.de.mats)
  end)

  it("lets go of greens older than MAX_DAYS and keeps at most MAX_GREENS", function()
    local sp = SnipeProfit.new({})
    local day = 86400
    sp:bought(1, nil, 100, 0, armor)
    sp:bought(2, nil, 100, 10 * day, armor)
    sp:prune((SnipeProfit.MAX_DAYS + 5) * day)
    assert.equal(1, #sp.store.greens)
    assert.equal(2, sp.store.greens[1].item)

    local old = SnipeProfit.MAX_GREENS
    SnipeProfit.MAX_GREENS = 2
    sp:bought(3, nil, 100, 11 * day, armor)
    sp:bought(4, nil, 100, 12 * day, armor)
    SnipeProfit.MAX_GREENS = old
    assert.same({ 3, 4 }, { sp.store.greens[1].item, sp.store.greens[2].item })
  end)

  it("starts a broken store over", function()
    local sp = SnipeProfit.new({ greens = "nope" })
    assert.same({}, sp.store.greens)
    assert.same({}, SnipeProfit.new(nil).store.greens)
  end)
end)
