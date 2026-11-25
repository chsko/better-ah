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
    assert.is_true(t.enabled)
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
end)
