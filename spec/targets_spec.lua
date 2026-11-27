local helper = require("spec.helper")

describe("Targets", function()
  local ns = helper.load("BetterAH/Core/Money.lua")
  helper.load("BetterAH/Core/Targets.lua", ns)
  local Targets = ns.Targets
  local band = { min = 26, max = 30 }

  local function target(types, profit)
    local set = {}
    for _, id in ipairs(types) do set[id] = true end
    return { types = set, band = 26, profit = profit or { kind = "gold", amount = 300 }, enabled = true }
  end

  it("tells item types from class, subclass and slot", function()
    assert.equal("cloth", Targets.typeOf({ classID = 4, subclassID = 1, equip = "INVTYPE_CLOAK" }))
    assert.equal("plate", Targets.typeOf({ classID = 4, subclassID = 4, equip = "INVTYPE_CHEST" }))
    assert.equal("shield", Targets.typeOf({ classID = 4, subclassID = 6, equip = "INVTYPE_SHIELD" }))
    assert.equal("jewelry", Targets.typeOf({ classID = 4, subclassID = 0, equip = "INVTYPE_FINGER" }))
    assert.is_nil(Targets.typeOf({ classID = 4, subclassID = 0, equip = "INVTYPE_TABARD" }), "misc, not jewelry")
    assert.equal("onehand", Targets.typeOf({ classID = 2, subclassID = 15 }))
    assert.equal("twohand", Targets.typeOf({ classID = 2, subclassID = 10 }))
    assert.equal("ranged", Targets.typeOf({ classID = 2, subclassID = 19 }))
    assert.is_nil(Targets.typeOf({ classID = 2, subclassID = 20 }), "fishing poles")
    assert.is_nil(Targets.typeOf({ classID = 7, subclassID = 1 }))
    assert.is_nil(Targets.typeOf(nil))
  end)

  it("takes sniped greens of its types in its band", function()
    local t = target({ "cloth", "leather" })
    local item = { quality = 2, level = 28, classID = 4, subclassID = 2, equip = "INVTYPE_WRIST" }
    assert.is_true(Targets.matches(t, band, item))
    assert.is_false(Targets.matches(t, band, { quality = 3, level = 28, classID = 4, subclassID = 2 }), "blue")
    assert.is_false(Targets.matches(t, band, { quality = 2, level = 31, classID = 4, subclassID = 2 }), "band")
    assert.is_false(Targets.matches(t, band, { quality = 2, level = 28, classID = 4, subclassID = 3 }), "mail")
    t.enabled = false
    assert.is_false(Targets.matches(t, band, item), "not sniped")
  end)

  it("works out the max price from a gold or percent profit", function()
    assert.equal(1120, Targets.maxPrice(target({ "cloth" }, { kind = "gold", amount = 300 }), 1420))
    assert.equal(784, Targets.maxPrice(target({ "cloth" }, { kind = "percent", amount = 20 }), 980))
    assert.equal(0, Targets.maxPrice(target({ "cloth" }, { kind = "gold", amount = 5000 }), 1420), "never below 0")
    assert.is_nil(Targets.maxPrice(target({ "cloth" }), nil), "no worth, no price")
  end)

  it("names its types and profit", function()
    assert.equal("Armor", Targets.typesText(target(Targets.ARMOR)))
    assert.equal("Weapons", Targets.typesText(target({ "onehand", "twohand", "ranged" })))
    assert.equal("Cloth, Mail", Targets.typesText(target({ "mail", "cloth" })))
    assert.equal("Cloth, Leather +2", Targets.typesText(target({ "cloth", "leather", "plate", "ranged" })))
    assert.equal("No item types", Targets.typesText(target({})))
    local all = {}
    for _, t in ipairs(Targets.TYPES) do all[#all + 1] = t.id end
    assert.equal("All gear", Targets.typesText(target(all)))
    assert.equal("3s 0c", Targets.profitText(target({ "cloth" })))
    assert.equal("20%", Targets.profitText(target({ "cloth" }, { kind = "percent", amount = 20 })))
    assert.same({ armor = true, weapon = true }, Targets.classes(target({ "cloth", "ranged" })))
  end)

  it("keeps targets in the saved list", function()
    local saved = {}
    local store = Targets.new(saved)
    local t, index = store:add(26)
    assert.equal(1, index)
    assert.equal(saved[1], t)
    assert.same({ cloth = true, leather = true, mail = true, plate = true }, t.types)
    assert.same({ kind = "percent", amount = 10 }, t.profit)
    assert.is_false(t.enabled, "a new target starts unticked (#206)")
    store:remove(1)
    assert.equal(0, #saved)
  end)

  it("reads item types from the game's item info", function()
    local fake = require("spec.fake_client")
    local env = fake.new()
    helper.load("BetterAH/Game/AuctionAPI.lua", ns)
    env.GetItemInfo = function()
      return "Ridgeback Bracers", "link", 2, 28, 23, "Armor", "Leather", 1, "INVTYPE_WRIST", 0, 100, 4, 2
    end
    local info = ns.AuctionAPI.new(env):itemInfo("i:1234")
    assert.equal("leather", Targets.typeOf(info))
    assert.equal(23, info.required)
    local t = target({ "leather" })
    assert.is_true(Targets.matches(t, band, info))
    assert.is_true(Targets.matches(t, band, { quality = 2, level = 30, classID = 4, subclassID = 2 }), "top of band")
    assert.is_true(Targets.matches(t, { min = 61, max = 99 }, { quality = 2, level = 65, classID = 4,
      subclassID = 2 }), "the open top band")
    assert.equal("jewelry", Targets.typeOf({ classID = 4, subclassID = 0, equip = "INVTYPE_NECK" }))
    assert.equal("jewelry", Targets.typeOf({ classID = 4, subclassID = 0, equip = "INVTYPE_TRINKET" }))
  end)

  it("reads item details from C_Item.GetItemInfo where the global is missing", function()
    local fake = require("spec.fake_client")
    local env = fake.new()
    helper.load("BetterAH/Game/AuctionAPI.lua", ns)
    env.GetItemInfo = nil
    env.C_Item.GetItemInfo = function()
      return "Ridgeback Bracers", "link", 2, 28, 23, "Armor", "Leather", 1, "INVTYPE_WRIST", 0, 100, 4, 2
    end
    assert.equal("leather", Targets.typeOf(ns.AuctionAPI.new(env):itemInfo("i:1234")))
  end)
  describe("best listing now (#246)", function()
    local leather = { quality = 2, level = 28, classID = 4, subclassID = 2, equip = "INVTYPE_WRIST" }
    local sword = { quality = 2, level = 28, classID = 2, subclassID = 7, equip = "INVTYPE_WEAPON" }
    local worth = { armor = 1000, weapon = 2000 }
    local function worthOf(class) return worth[class] end

    it("picks the listing with the most profit among those the target takes", function()
      local t = target({ "leather", "onehand" }, { kind = "percent", amount = 10 })
      local best = Targets.best(t, band, {
        { item = "i:1", price = 950, info = leather },
        { item = "i:2", price = 1500, info = sword },
        { item = "i:3", price = 100, info = { quality = 3, level = 28, classID = 4, subclassID = 2 } }, -- blue
        { item = "i:4", price = 100, info = { quality = 2, level = 40, classID = 4, subclassID = 2 } }, -- band
        { item = "i:5", price = 100, info = { quality = 2, level = 28, classID = 4, subclassID = 4 } }, -- plate
        { item = "i:6", price = 0, info = leather }, -- no buyout
        { item = "i:7", price = 100 }, -- not loaded
      }, worthOf)
      assert.same({ item = "i:2", price = 1500, worth = 2000, profit = 500, max = 1800, status = "buy" }, best)
    end)

    it("counts unticked targets too", function()
      local t = target({ "leather" })
      t.enabled = false
      assert.equal("i:1", Targets.best(t, band, { { item = "i:1", price = 500, info = leather } }, worthOf).item)
    end)

    it("says whether the sniper would buy, the profit is short, or it loses", function()
      local t = target({ "leather" }, { kind = "gold", amount = 200 }) -- max 800
      local function status(price)
        return Targets.best(t, band, { { item = "i:1", price = price, info = leather } }, worthOf).status
      end
      assert.equal("buy", status(800), "at the max")
      assert.equal("short", status(801))
      assert.equal("short", status(999))
      assert.equal("loss", status(1000), "no profit")
      assert.equal("loss", status(1200))
      assert.equal(-200, Targets.best(t, band, { { item = "i:1", price = 1200, info = leather } }, worthOf).profit)
    end)

    it("never says buy when the profit takes the whole worth", function()
      local t = target({ "leather" }, { kind = "percent", amount = 100 })
      assert.equal("short", Targets.best(t, band, { { item = "i:1", price = 1, info = leather } }, worthOf).status)
    end)

    it("has nothing without a listing it takes or a worth", function()
      local t = target({ "leather" })
      assert.is_nil(Targets.best(t, band, {}, worthOf))
      assert.is_nil(Targets.best(t, band, nil, worthOf))
      assert.is_nil(Targets.best(t, band, { { item = "i:1", price = 500, info = leather } }, function() return nil end))
      assert.is_nil(Targets.best(t, nil, { { item = "i:1", price = 500, info = leather } }, worthOf))
    end)

    it("puts a listing the sniper buys before a short one with more profit", function()
      local t = target({ "leather", "onehand" }, { kind = "percent", amount = 10 })
      local best = Targets.best(t, band, { { item = "i:2", price = 1820, info = sword }, -- 180 profit, max 1800
        { item = "i:1", price = 850, info = leather } }, worthOf) -- 150 profit, max 900
      assert.equal("i:1", best.item)
      assert.equal("buy", best.status)
    end)

    it("breaks a profit tie by the lower price", function()
      local t = target({ "leather", "onehand" })
      local best = Targets.best(t, band, { { item = "i:2", price = 1500, info = sword },
        { item = "i:1", price = 500, info = leather } }, function(class) return class == "armor" and 1000 or 2000 end)
      assert.equal("i:1", best.item)
    end)
  end)
  it("signs a target by its band and item types (#246)", function()
    local a = target({ "leather", "cloth" })
    assert.equal("26:cloth,leather", Targets.signature(a))
    local b = target({ "cloth", "leather" }, { kind = "percent", amount = 50 })
    b.enabled = false
    assert.equal(Targets.signature(a), Targets.signature(b), "profit and ticks don't change the query")
    b.band = 31
    assert.are_not.equal(Targets.signature(a), Targets.signature(b))
  end)
end)
