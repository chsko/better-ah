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

  it("takes the 5% auction house cut and deposits off what the materials sell for", function()
    assert.equal(950, Disenchant.net(1000))
    assert.equal(940, Disenchant.net(1000, 10))
    assert.is_nil(Disenchant.net(nil))
  end)
end)
