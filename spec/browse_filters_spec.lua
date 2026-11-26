local helper = require("spec.helper")

describe("BrowseFilters", function()
  local F
  before_each(function() F = helper.load("BetterAH/Core/BrowseFilters.lua").BrowseFilters end)

  -- Shaped like Blizzard's AuctionCategories: parents hold their children's filters too.
  local mail = { name = "Mail", filters = { { classID = 4, subClassID = 3 } },
    subCategories = { { name = "Chest", filters = { { classID = 4, subClassID = 3, inventoryType = 5 } } } } }
  local blizzard = {
    { name = "Weapons", filters = { { classID = 2, subClassID = 0 } } },
    { name = "Armor", filters = { { classID = 4, subClassID = 3 } }, subCategories = { mail },
      parent = "loops are not followed" },
    { name = "Quest Items", filters = { { classID = 12 } }, implicitFilter = 99 },
    { name = "WoW Token", filters = { { classID = 18 } }, flags = { WOW_TOKEN_FLAG = true } },
    { name = "" }, "junk",
  }

  it("copies the client's category tree, leaving out the WoW Token", function()
    local tree = F.tree(blizzard)
    assert.equal(3, #tree)
    assert.equal("Armor", tree[2].name)
    assert.same({ { classID = 4, subClassID = 3 } }, tree[2].filters)
    assert.equal("Chest", tree[2].children[1].children[1].name)
    assert.equal(99, tree[3].implicitFilter)
    assert.equal(0, #F.tree(blizzard, 1)[2].children, "depth limits the levels")
    assert.same({}, F.tree(nil))
  end)

  it("finds a category by its path of names", function()
    local tree = F.tree(blizzard)
    assert.equal("Chest", F.find(tree, { "Armor", "Mail", "Chest" }).name)
    assert.equal("Armor", F.find(tree, { "Armor" }).name)
    assert.is_nil(F.find(tree, { "Armor", "Plate" }))
    assert.is_nil(F.find(tree, {}))
    assert.equal("Armor / Mail", F.label({ "Armor", "Mail" }))
  end)

  it("starts with every rarity on and the rest off, and fills in a broken saved state", function()
    local d = F.defaults()
    assert.is_false(d.usable)
    assert.is_true(d.rarity.poor and d.rarity.legendary)
    assert.is_true(F.isDefault(d))
    local s = F.normalize({ usable = true, rarity = { poor = false, rare = "yes" } })
    assert.is_true(s.usable)
    assert.is_false(s.rarity.poor)
    assert.is_false(s.rarity.rare)
    assert.is_true(s.rarity.epic)
    assert.is_false(F.isDefault(s))
    assert.is_true(F.isDefault("junk"))
  end)

  it("turns chips and a category into the query's filter values", function()
    assert.same({ 6, 7, 8, 9, 10, 11 }, F.filters(F.defaults()))
    local s = F.defaults()
    s.usable, s.exact, s.rarity.poor, s.rarity.common = true, true, false, false
    assert.same({ 2, 5, 8, 9, 10, 11, 99 }, F.filters(s, { implicitFilter = 99 }))
    for _, r in ipairs(F.RARITIES) do s.rarity[r.key] = false end
    assert.same({ 2, 5, 6, 7, 8, 9, 10, 11 }, F.filters(s), "no rarity at all means every rarity")
  end)

  it("words the rarity chips that are on", function()
    local s = F.defaults()
    assert.is_nil(F.rarityText(s), "all of them")
    s.rarity.poor, s.rarity.common = false, false
    assert.equal("Uncommon and up", F.rarityText(s))
    s.rarity.legendary = false
    assert.equal("Uncommon to Epic", F.rarityText(s))
    s.rarity.uncommon, s.rarity.epic = false, false
    assert.equal("Rare", F.rarityText(s))
    s.rarity.poor = true
    assert.equal("Poor, Rare", F.rarityText(s))
  end)

  it("keeps filters in the search history and gets the same chips back", function()
    local s = F.defaults()
    s.usable, s.rarity.poor = true, false
    local h = F.historyFilters(s)
    assert.same({ "usable", "rarity:common+uncommon+rare+epic+legendary" }, { h[1].key, h[2].key })
    assert.equal("usable by me", h[1].label)
    assert.equal("Common and up", h[2].label)
    assert.same(s, F.fromHistory(h))
    assert.same({}, F.historyFilters(F.defaults()), "the defaults add nothing")
    assert.same(F.defaults(), F.fromHistory(nil))
  end)
end)
