local helper = require("spec.helper")

describe("Disenchant", function()
  local Disenchant = helper.load("BetterAH/Core/Disenchant.lua").Disenchant

  local function ids(yields)
    local out = {}
    for _, y in ipairs(yields) do out[#out + 1] = y.id .. "@" .. y.chance end
    return out
  end

  it("has a base group of the 24 disenchant materials", function()
    assert.equal(24, #Disenchant.MATERIALS)
    assert.equal("Illusion Dust", Disenchant.BY_ID[16204].name)
  end)

  it("gives green armor mostly dust and green weapons mostly essence", function()
    local armor = Disenchant.yields({ quality = 2, class = "armor", level = 58, equip = "INVTYPE_CHEST" })
    assert.same({ "16204@0.75", "16203@0.2", "14344@0.05" }, ids(armor))
    local weapon = Disenchant.yields({ quality = 2, classID = 2, level = 58, equip = "INVTYPE_WEAPON" })
    assert.same({ "16204@0.2", "16203@0.75", "14344@0.05" }, ids(weapon))
    assert.equal(1.125, armor[1].expected, "75% of 1-2")
  end)

  it("uses Forever's Greater Magic Essence for weapons of item level 21-30", function()
    assert.same({ "10940@0.15", "10939@0.75", "10978@0.1" }, ids(Disenchant.yields({ quality = 2, class = "weapon",
      level = 23 })))
    assert.same({ "11083@0.2", "10939@0.75", "11084@0.05" }, ids(Disenchant.yields({ quality = 2, class = "weapon",
      level = 28 })))
    assert.same({ "11083@0.75", "11082@0.2", "11084@0.05" }, ids(Disenchant.yields({ quality = 2, class = "armor",
      level = 28 })))
  end)

  it("covers every green item level from 5 to 99 for armor and weapons", function()
    for _, class in ipairs({ "armor", "weapon" }) do
      for level = 5, 99 do
        assert.is_not_nil(Disenchant.yields({ quality = 2, class = class, level = level }), class .. " " .. level)
      end
    end
  end)

  it("covers blues from item level 5 (armor) or 16 (weapons), and epics from 40, up to 99", function()
    for level = 5, 99 do
      assert.is_not_nil(Disenchant.yields({ quality = 3, class = "armor", level = level }), "blue armor " .. level)
      assert.equal(level >= 16, Disenchant.yields({ quality = 3, class = "weapon", level = level }) ~= nil,
        "blue weapon " .. level)
      assert.equal(level >= 40, Disenchant.yields({ quality = 4, class = "armor", level = level }) ~= nil,
        "epic " .. level)
    end
    assert.same({ "14344@0.995", "20725@0.005" }, ids(Disenchant.yields({ quality = 3, class = "armor", level = 58 })))
  end)

  it("gives blues a shard and epics shards or a Nexus Crystal", function()
    assert.same({ "14343@1" }, ids(Disenchant.yields({ quality = 3, class = "weapon", level = 53 })))
    assert.same({ "20725@1" }, ids(Disenchant.yields({ quality = 4, class = "armor", level = 60 })))
    assert.equal(3, Disenchant.yields({ quality = 4, class = "armor", level = 44 })[1].expected)
  end)

  it("says why an item doesn't disenchant", function()
    local function why(info) return select(2, Disenchant.yields(info)) end
    assert.equal("only green, blue and purple items disenchant", why({ quality = 1, class = "armor", level = 20 }))
    assert.equal("only armor and weapons disenchant", why({ quality = 2, classID = 0, level = 20 }))
    assert.equal("this item can't be disenchanted", why({ quality = 2, class = "armor", level = 20,
      equip = "INVTYPE_TABARD" }))
    assert.equal("this item can't be disenchanted", why({ id = 2575, quality = 2, class = "armor", level = 20 }))
    assert.equal("item details not loaded yet", why({ quality = 2, class = "armor" }))
  end)

  it("values a disenchant at its materials' market values", function()
    local prices = { [16204] = 200, [16203] = 1000, [14344] = 4000 }
    local value, breakdown, missing, _ = Disenchant.value({ quality = 2, class = "armor", level = 58 },
      function(id) return prices[id] end)
    -- 1.125 * 200 + 0.3 * 1000 + 0.05 * 4000
    assert.equal(725, value)
    assert.equal(0, missing)
    assert.same({ 225, 300, 200 }, { breakdown[1].value, breakdown[2].value, breakdown[3].value })
    prices[14344] = nil
    value, _, missing = Disenchant.value({ quality = 2, class = "armor", level = 58 },
      function(id) return prices[id] end)
    assert.same({ 525, 1 }, { value, missing }, "a material without a price counts as nothing, and is reported")
    assert.is_nil((Disenchant.value({ quality = 2, class = "armor", level = 58 }, function() return nil end)))
    assert.equal("no disenchant data for item level 30",
      select(4, Disenchant.value({ quality = 4, class = "armor", level = 30 })))
  end)

  it("adds the Arcane Salvager's 50% chance of one extra dust or essence", function()
    -- Christian's spreadsheet, uncommon armor 26-30, prices in silver: (dust * 1.5 + essence * 0.4 + shard * 0.05)
    -- * 0.95 = 14.20s with Soul Dust 4s 46c, Greater Astral Essence 15s 68c, Large Glimmering Shard 39s 78c.
    local prices = { [11083] = 446, [11082] = 1568, [11084] = 3978 }
    local info = { quality = 2, class = "armor", level = 28 }
    local yields = Disenchant.yields(info, { salvager = true })
    assert.same({ 1.5, 0.4, 0.05 }, { yields[1].expected, yields[2].expected, yields[3].expected })
    local value = Disenchant.value(info, function(id) return prices[id] end, { salvager = true })
    assert.equal(1420, Disenchant.net(value))
    assert.equal(1.125, Disenchant.yields(info)[1].expected, "without it")
    assert.equal(1, Disenchant.yields({ quality = 3, class = "armor", level = 28 }, { salvager = true })[1].expected,
      "shards get no extra")
  end)

  it("lists the green bands with their usual required levels", function()
    local bands = Disenchant.greenBands()
    assert.equal(11, #bands)
    assert.same({ min = 26, max = 30, required = { min = 21, max = 25 } }, bands[4])
    assert.same({ min = 5, max = 15, required = { min = 1, max = 10 } }, bands[1])
  end)

  it("takes the 5% auction house cut and deposits off what the materials sell for", function()
    assert.equal(950, Disenchant.net(1000))
    assert.equal(940, Disenchant.net(1000, 10))
    assert.is_nil(Disenchant.net(nil))
  end)
  it("says whether an Arcane Salvager adds anything", function()
    assert.is_true(Disenchant.salvagerAdds(Disenchant.yields({ quality = 2, class = "armor", level = 28 })))
    assert.is_false(Disenchant.salvagerAdds(Disenchant.yields({ quality = 3, class = "armor", level = 40 })),
      "shards only")
    assert.is_false(Disenchant.salvagerAdds(nil))
  end)
  it("prices a lesser essence at a third of the greater one when that is more, as three combine", function()
    local prices = { [11135] = 2291, [11134] = 500, [11083] = 446 }
    local function priceOf(id) return prices[id] end
    assert.equal(763, Disenchant.priceOf(11134, priceOf), "a third of Greater Mystic beats 5s, in whole copper")
    prices[11134] = 900
    assert.equal(900, Disenchant.priceOf(11134, priceOf), "its own price when higher")
    prices[11134] = nil
    assert.equal(763, Disenchant.priceOf(11134, priceOf), "no listings of its own")
    assert.equal(446, Disenchant.priceOf(11083, priceOf), "dust is just its price")
    assert.is_nil(Disenchant.priceOf(11138, priceOf))
    -- The spreadsheet's 31-35 row: ((dust*3)+(greater*0.33*0.4)+(shard*0.05))*0.95 with Soul Dust 4.46s,
    -- Greater Mystic 22.91s and Small Glowing Shard 8.4s gives 15.98s; a true third gives 16.00s.
    prices[11138] = 840
    local value = Disenchant.value({ quality = 2, class = "armor", level = 33 }, priceOf, { salvager = true })
    assert.equal(1600, Disenchant.net(value))
  end)

  describe("buyPriceOf (#250)", function()
    local NOW = 100 * 86400 + 3600
    local market = { [10940] = 500, [10939] = 2400, [11083] = 300 }
    local current = {
      [10940] = { lowest = 350, listed = true, seen = NOW - 600 },
      [10939] = { lowest = 3000, listed = true, seen = NOW - 600 },
      [11083] = { lowest = 100, listed = true, seen = NOW - 86400 - 1 },
      [11084] = { lowest = 900, listed = true, seen = NOW - 60 },
      [11138] = { lowest = nil, quantity = 0, listed = false, seen = NOW - 60 },
      [11134] = { lowest = 50, listed = false, seen = NOW },
      [11135] = { lowest = 0, listed = true, seen = NOW },
      [11137] = { lowest = 49, listed = true, seen = NOW },
      [11176] = { lowest = 400, listed = true, seen = NOW - 86400 },
    }
    market[11134], market[11135], market[11137], market[11176] = 800, 700, 500, 600
    local priceOf = Disenchant.buyPriceOf(function(id) return market[id] end,
      function(id) return current[id] end, NOW)

    it("takes the cheapest listing when it is under market value", function()
      assert.equal(350, priceOf(10940))
    end)

    it("keeps market value when the cheapest is above it", function()
      assert.equal(2400, priceOf(10939))
    end)

    it("ignores a cheapest listing older than a day", function()
      assert.equal(300, priceOf(11083))
    end)

    it("uses the cheapest alone when there is no market value", function()
      assert.equal(900, priceOf(11084))
    end)

    it("is nil when neither is known, and ignores a mat no longer listed", function()
      assert.is_nil(priceOf(11138))
      assert.is_nil(priceOf(16204))
    end)

    it("ignores a cheapest a later full scan didn't list, or of no copper", function()
      assert.equal(800, priceOf(11134))
      assert.equal(700, priceOf(11135))
    end)

    it("ignores a troll cheapest below a tenth of market value", function()
      assert.equal(500, priceOf(11137))
    end)

    it("still counts a cheapest seen exactly a day ago", function()
      assert.equal(400, priceOf(11176))
    end)

    it("takes a market value lookup that returns more than one value", function()
      local p = Disenchant.buyPriceOf(function() return 500, { days = 3 } end, nil, NOW)
      assert.equal(500, p(10940))
    end)

    it("works without a current lookup", function()
      assert.equal(500, Disenchant.buyPriceOf(function(id) return market[id] end, nil, NOW)(10940))
    end)

    it("feeds the essence rule: a lesser is still worth a third of the cheaper greater", function()
      local m = { [10938] = 1000, [10939] = 2400 }
      local c = { [10939] = { lowest = 1500, listed = true, seen = NOW } }
      local p = Disenchant.buyPriceOf(function(id) return m[id] end, function(id) return c[id] end, NOW)
      assert.equal(1000, Disenchant.priceOf(10938, p))
      m[10938] = 300
      assert.equal(500, Disenchant.priceOf(10938, p))
    end)
  end)
end)
