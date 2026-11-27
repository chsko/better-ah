local helper = require("spec.helper")

describe("TooltipPrices", function()
  local TooltipPrices = helper.load("BetterAH/Core/TooltipPrices.lua").TooltipPrices
  local on = TooltipPrices.options({})

  local function rows(out)
    local list = {}
    for i, r in ipairs(out.rows) do list[i] = r.label .. "=" .. r.money end
    return list
  end

  it("shows a sniped green's value, disenchant value, price paid and both profits (mockup A)", function()
    local out = TooltipPrices.lines({ value = 42000, disenchant = 38500, paid = { unit = 21000, units = 1 },
      bags = 1 }, on)
    assert.equal("Better AH", out.title)
    assert.is_nil(out.note)
    assert.same({ "Market value=42000", "Disenchant value=38500", "You paid=21000", "Profit if sold=18900",
      "Profit if disenchanted=15500" }, rows(out))
    assert.is_true(out.rows[4].sign)
    assert.is_nil(out.hint, "one in the bags: nothing to total")
  end)

  it("prices a stack each, with the average paid and a Shift hint (mockup B)", function()
    local out = TooltipPrices.lines({ value = 2140, paid = { unit = 1780, units = 12 }, stackable = true, bags = 34 },
      on)
    assert.equal("(each)", out.note)
    assert.same({ "Market value=2140", "You paid, average=1780", "Profit if sold=253" }, rows(out))
    assert.equal("Hold Shift for all 34 in your bags", out.hint)
  end)

  it("totals everything in the bags while Shift is held, profit only for the units with a price (mockup C)", function()
    local out = TooltipPrices.lines({ value = 2140, paid = { unit = 1780, units = 12 }, stackable = true, bags = 34,
      shift = true }, on)
    assert.equal("(34 in bags)", out.note)
    assert.same({ "Market value=72700", "You paid (12 of 34)=21300", "Profit if sold (those 12)=3036" }, rows(out))
    assert.is_nil(out.hint)
  end)

  it("leaves out paid and profit for an item not bought through Better AH (mockup D)", function()
    local out = TooltipPrices.lines({ value = 26500, disenchant = 29000, bags = 1 }, on)
    assert.same({ "Market value=26500", "Disenchant value=29000" }, rows(out))
  end)

  it("says so when an item has no price (mockup E)", function()
    local out = TooltipPrices.lines({ bags = 1 }, on)
    assert.equal(TooltipPrices.NO_PRICE, out.message)
    assert.same({}, rows(out))
  end)

  it("shows a loss as a negative profit", function()
    local out = TooltipPrices.lines({ value = 1000, paid = { unit = 1200, units = 1 } }, on)
    assert.equal(-250, out.rows[3].money)
  end)

  it("follows the settings", function()
    local item = { value = 2140, disenchant = 900, paid = { unit = 1780, units = 12 }, stackable = true, bags = 34,
      shift = true }
    assert.is_nil(TooltipPrices.lines(item, TooltipPrices.options({ show = false })))
    local out = TooltipPrices.lines(item, TooltipPrices.options({ disenchant = false, paid = false, shift = false }))
    assert.same({ "Market value=2140" }, rows(out), "no totals with Shift off, and no hint")
    assert.is_nil(out.hint)
  end)

  it("keeps what is turned off, so a new part starts on", function()
    local saved = {}
    TooltipPrices.set(saved, "paid", false)
    assert.same({ paid = false }, saved)
    assert.same({ show = true, disenchant = true, paid = false, shift = true, lowest = true }, TooltipPrices.options(saved))
    TooltipPrices.set(saved, "paid", true)
    assert.same({}, saved)
  end)

  it("rounds money from 1 gold up to the silver", function()
    assert.equal(253, TooltipPrices.round(253))
    assert.equal(72700, TooltipPrices.round(72760))
    assert.equal(-15500, TooltipPrices.round(-15575))
  end)
end)

describe("TooltipPrices, min buyout (#194)", function()
  local ns = helper.load("BetterAH/Core/Time.lua")
  local TooltipPrices = helper.load("BetterAH/Core/TooltipPrices.lua", ns).TooltipPrices
  local on = TooltipPrices.options({})

  it("shows the cheapest buyout from the latest scan and how old it is", function()
    local out = TooltipPrices.lines({ value = 2140, stackable = true, bags = 1, now = 7200,
      current = { lowest = 1990, listed = true, seen = 0 } }, on)
    assert.same({ label = "Min buyout (2 h ago)", money = 1990 }, out.rows[2])
  end)

  it("says none listed when the latest scan didn't list it", function()
    local out = TooltipPrices.lines({ value = 2140, bags = 1, now = 600,
      current = { listed = false, seen = 0 } }, on)
    assert.same({ label = "Min buyout (10 min ago)", text = "none listed" }, out.rows[2])
  end)

  it("says each beside the bag totals, and goes with its setting", function()
    local item = { value = 2140, stackable = true, bags = 5, shift = true, now = 0,
      current = { lowest = 1990, listed = true, seen = 0 } }
    assert.equal("Min buyout, each (just now)", TooltipPrices.lines(item, on).rows[2].label)
    assert.equal(1, #TooltipPrices.lines(item, TooltipPrices.options({ lowest = false })).rows)
  end)
end)
