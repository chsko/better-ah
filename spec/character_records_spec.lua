local helper = require("spec.helper")

describe("CharacterRecords", function()
  local CharacterRecords = helper.load("BetterAH/Core/CharacterRecords.lua").CharacterRecords

  local function setup()
    local store = {}
    local r = CharacterRecords.new(store)
    r:setCharacter("Thrall-6841", { name = "Thrall", faction = "Horde" })
    r:setCharacter("Jaina-6946", { name = "Jaina", faction = "Alliance" })
    r:setPlace("Thrall-6841", "bags", {
      { item = "i:2589", count = 20, name = "Linen Cloth" }, { item = "i:2589", count = 5 },
      { item = "i:2592", count = 3, name = "Wool Cloth" },
    }, 100)
    r:setPlace("Thrall-6841", "bank", { { item = "i:2589", count = 40 } }, 101)
    r:setPlace("Jaina-6946", "auctions", { { item = "i:2589", count = 10 } }, 102)
    return r, store
  end

  it("totals an item across characters and places", function()
    local r = setup()
    local total, by = r:count("i:2589")
    assert.equal(75, total)
    assert.same({
      { key = "Jaina-6946", name = "Jaina", total = 10, bags = 0, bank = 0, auctions = 10 },
      { key = "Thrall-6841", name = "Thrall", total = 65, bags = 25, bank = 40, auctions = 0 },
    }, by)
    assert.equal(0, (r:count("i:1")))
  end)

  it("lists every owned item by name with its total and how many characters have it", function()
    local r = setup()
    assert.same({
      { item = "i:2589", name = "Linen Cloth", total = 75, characters = 2 },
      { item = "i:2592", name = "Wool Cloth", total = 3, characters = 1 },
    }, r:items())
  end)

  it("replaces a place wholesale, so items that left are gone", function()
    local r = setup()
    r:setPlace("Thrall-6841", "bags", { { item = "i:2592", count = 1 } }, 200)
    assert.equal(50, (r:count("i:2589")))
    assert.equal(1, (r:count("i:2592")))
  end)

  it("names unnamed items with the caller's lookup and puts the rest last", function()
    local r = CharacterRecords.new({})
    r:setPlace("A", "bags", { { item = "i:9", count = 1 }, { item = "i:8", count = 1 },
      { item = "i:7", count = 1, name = "zebra" } }, 1)
    local names = {}
    for _, it in ipairs(r:items(function(item) return item == "i:9" and "Apple" or "" end)) do
      names[#names + 1] = it.name or it.item
    end
    assert.same({ "Apple", "zebra", "i:8" }, names)
  end)

  it("keeps when each place was last read and survives a reload from the saved table", function()
    local _, store = setup()
    local r = CharacterRecords.new(store)
    local chars = r:characters()
    assert.same({ "Jaina", "Thrall" }, { chars[1].name, chars[2].name })
    assert.same({ bags = 100, bank = 101 }, chars[2].seen)
    assert.equal(75, (r:count("i:2589")))
  end)

  it("ignores unknown places, empty slots and zero counts", function()
    local r = CharacterRecords.new({})
    assert.is_false(r:setPlace("A", "mailbox", {}, 1))
    local items = { { item = "i:1", count = 0 }, { count = 3 }, { item = "i:2", count = 2 } }
    assert.is_true(r:setPlace("A", "bags", items, 1))
    assert.same({ { item = "i:2", total = 2, characters = 1 } }, r:items())
  end)
end)
