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

describe("SnipeProfit:results (#257)", function()
  local ns = helper.load("BetterAH/Core/Purchases.lua")
  helper.load("BetterAH/Core/Disenchant.lua", ns)
  local SnipeProfit = helper.load("BetterAH/Core/SnipeProfit.lua", ns).SnipeProfit
  local DUST, ESSENCE = 10940, 10998
  local armor = { name = "Armor", min = 21, max = 25, profit = "2g", worth = 12000 }
  local weapons = { name = "Weapons", min = 21, max = 25, profit = "1g", worth = 15000 }
  local function sale(t, item, n, c, cut, nameOnly)
    return { k = "sale", t = t, item = not nameOnly and item or nil,
      name = nameOnly and ns.Disenchant.BY_ID[item].name or "x", n = n, c = c, cut = cut or 0 }
  end
  local function none() return nil end
  local function rowOf(r, name)
    for _, row in ipairs(r.rows) do if row.name == name then return row end end
  end

  it("credits a mat sale to the disenchant that gave the mats", function()
    local sp = SnipeProfit.new({})
    sp:bought(1, nil, 5000, 10, armor)
    sp:disenchanted(1, nil, "A", 20, { [DUST] = 4 })
    local r = sp:results(0, { sale(30, DUST, 4, 8000, 400) }, none)
    local row = r.rows[1]
    assert.same({ "Armor", 21, 25, "2g" }, { row.name, row.min, row.max, row.targetProfit })
    assert.same({ 1, 1, 5000, 7600, 0, 2600 }, { row.greens, row.disenchanted, row.spent, row.earned,
      row.unsold, row.profit })
    assert.same({ got = 4, sold = 4, held = 0, earned = 7600, unsold = 0 }, row.mats[DUST])
  end)

  it("splits one sale over several disenchants, oldest first", function()
    local sp = SnipeProfit.new({})
    sp:bought(1, nil, 5000, 10, armor)
    sp:bought(2, nil, 6000, 11, weapons)
    sp:disenchanted(2, nil, "A", 20, { [DUST] = 3 })
    sp:disenchanted(1, nil, "A", 21, { [DUST] = 3 })
    local r = sp:results(0, { sale(30, DUST, 4, 4000) }, none)
    assert.equal(3000, rowOf(r, "Weapons").earned, "disenchanted first, sold first")
    assert.equal(1000, rowOf(r, "Armor").earned)
    assert.same({ got = 3, sold = 1, held = 2, earned = 1000, unsold = 0 }, rowOf(r, "Armor").mats[DUST])
  end)

  it("values mats not sold yet at what the caller says a unit brings", function()
    local sp = SnipeProfit.new({})
    sp:bought(1, nil, 5000, 10, armor)
    sp:disenchanted(1, nil, "A", 20, { [DUST] = 5, [ESSENCE] = 1 })
    local r = sp:results(0, { sale(30, DUST, 2, 2000) }, function(id) return id == DUST and 900 or nil end)
    local row = r.rows[1]
    assert.equal(2000, row.earned)
    assert.equal(2700, row.unsold, "3 dust at 9s; the essence has no value known")
    assert.equal(-300, row.profit)
  end)

  it("ignores sales made before the disenchant and units sold beyond what was disenchanted", function()
    local sp = SnipeProfit.new({})
    sp:bought(1, nil, 5000, 10, armor)
    sp:disenchanted(1, nil, "A", 20, { [DUST] = 2 })
    local r = sp:results(0, { sale(15, DUST, 10, 10000), sale(30, DUST, 5, 5000) }, none)
    assert.equal(2000, r.rows[1].earned, "2 of the 5 later units, at 10s each")
  end)

  it("matches a sale known only by its mail name", function()
    local sp = SnipeProfit.new({})
    sp:bought(1, nil, 5000, 10, armor)
    sp:disenchanted(1, nil, "A", 20, { [DUST] = 2 })
    local r = sp:results(0, { sale(30, DUST, 2, 3000, 150, true), { k = "buy", t = 31, item = DUST, n = 2, c = 99 } },
      none)
    assert.equal(2850, r.rows[1].earned)
  end)

  it("counts greens not disenchanted yet as spent and waiting, at the worth the sniper saw", function()
    local sp = SnipeProfit.new({})
    sp:bought(1, nil, 5000, 10, armor)
    sp:bought(1, nil, 6000, 11, armor)
    sp:disenchanted(1, nil, "A", 20, { [DUST] = 2 })
    local row = sp:results(0, {}, none).rows[1]
    assert.same({ 2, 1, 11000 }, { row.greens, row.disenchanted, row.spent })
    assert.same({ n = 1, worth = 12000 }, row.waiting)
    assert.equal(-11000, row.profit, "the waiting worth is a guess and stays out of the profit")
  end)

  it("counts only greens bought since from, but matches sales over every green", function()
    local sp = SnipeProfit.new({})
    sp:bought(1, nil, 5000, 10, armor)
    sp:bought(1, nil, 6000, 100, armor)
    sp:disenchanted(1, nil, "A", 20, { [DUST] = 2 })
    sp:disenchanted(1, nil, "A", 110, { [DUST] = 2 })
    local r = sp:results(50, { sale(120, DUST, 3, 3000) }, none)
    local row = r.rows[1]
    assert.same({ 1, 6000, 1000 }, { row.greens, row.spent, row.earned },
      "the older green's dust sold first, and it is outside the period")
  end)

  it("keeps a row per target and band, Not sniped last, and a total", function()
    local sp = SnipeProfit.new({})
    sp:bought(1, nil, 5000, 10, { name = "Armor", min = 26, max = 30 })
    sp:bought(2, nil, 4000, 11, armor)
    sp:bought(3, nil, 3000, 12, weapons)
    sp:disenchanted(9, nil, "A", 20, { [DUST] = 1 }, 2500)
    local r = sp:results(0, { sale(30, DUST, 1, 1000) }, none)
    local names = {}
    for _, row in ipairs(r.rows) do names[#names + 1] = row.name .. " " .. tostring(row.min) end
    assert.same({ "Armor 21", "Armor 26", "Weapons 21", "Not sniped nil" }, names)
    local other = r.rows[4]
    assert.is_true(other.other)
    assert.same({ 1, 2500, 1000, -1500 }, { other.greens, other.spent, other.earned, other.profit })
    assert.same({ 4, 3, 14500, 1000, -13500 }, { r.total.greens, r.total.waiting.n, r.total.spent,
      r.total.earned, r.total.profit })
  end)

  it("makes the total add up to the rows it shows", function()
    local sp = SnipeProfit.new({})
    for i = 1, 3 do
      sp:bought(i, nil, 10, i, { name = "T" .. i, min = 21, max = 25 })
      sp:disenchanted(i, nil, "A", 10 + i, { [DUST] = 1 })
    end
    local r = sp:results(0, { sale(30, DUST, 3, 100) }, none)
    assert.same({ 33, 33, 33 }, { r.rows[1].earned, r.rows[2].earned, r.rows[3].earned })
    assert.equal(99, r.total.earned)
  end)

  it("stays quick with a long history", function()
    local sp = SnipeProfit.new({})
    for i = 1, 5000 do
      sp:bought(1, nil, 100, i, armor)
      sp:disenchanted(1, nil, "A", i, { [DUST] = 1 })
    end
    local sales = {}
    for i = 1, 20000 do sales[i] = sale(5000 + i, DUST, 1, 10) end
    local start = os.clock()
    local r = sp:results(0, sales, none)
    assert.equal(50000, r.total.earned)
    assert.is_true(os.clock() - start < 0.5, "took " .. (os.clock() - start) .. " s")
  end)

  it("gives no rows when nothing was bought", function()
    local r = SnipeProfit.new({}):results(0, nil, none)
    assert.same({}, r.rows)
    assert.equal(0, r.total.profit)
  end)
end)
