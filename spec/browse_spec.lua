local helper = require("spec.helper")

describe("Browse", function()
  local Browse
  before_each(function()
    local ns = helper.load("BetterAH/Core/BrowseFilters.lua")
    Browse = helper.load("BetterAH/Core/Browse.lua", ns).Browse
  end)

  describe("query", function()
    it("searches the name as typed, trimmed, with no level limits by default", function()
      local q = Browse.query({ text = "  Linen Cloth ", minLevel = "", maxLevel = "" })
      assert.equal("Linen Cloth", q.searchString)
      assert.equal(0, q.minLevel)
      assert.equal(0, q.maxLevel)
      assert.same({}, q.filters)
      assert.same({}, q.itemClassFilters)
      assert.same({ { sortOrder = 0, reverseSort = false } }, q.sorts, "cheapest first from the server")
    end)

    it("searches an item link's name", function()
      local link = "|cff1eff00|Hitem:15011::::::::20:::::|h[Ridgeback Bracers]|h|r"
      assert.equal("Ridgeback Bracers", Browse.query({ text = link }).searchString)
    end)

    it("takes a level range and swaps one typed the wrong way round", function()
      local q = Browse.query({ text = "", minLevel = "30", maxLevel = "21" })
      assert.equal(21, q.minLevel)
      assert.equal(30, q.maxLevel)
      q = Browse.query({ minLevel = 25 })
      assert.equal(25, q.minLevel)
      assert.equal(0, q.maxLevel)
    end)

    it("searches a category with its item class filters, chips and implicit filter", function()
      local category = { name = "Mail", filters = { { classID = 4, subClassID = 3 } }, implicitFilter = 99 }
      local q = Browse.query({ text = "", category = category, path = { "Armor", "Mail" },
        chips = { usable = true, rarity = { poor = false } } })
      assert.same({ { classID = 4, subClassID = 3 } }, q.itemClassFilters)
      assert.same({ 2, 7, 8, 9, 10, 11, 99 }, q.filters)
      assert.same({ "Armor", "Mail" }, q.path)
      assert.equal('3 items in Armor / Mail, level 21-30', Browse.summary(3, { searchString = "", minLevel = 21,
        maxLevel = 30, path = { "Armor", "Mail" } }))
      assert.same({ 6, 7, 8, 9, 10, 11 }, Browse.query({ chips = {} }).filters, "chips alone send the rarities")
    end)

    it("refuses levels that aren't whole numbers in range", function()
      for _, bad in ipairs({ "abc", "-1", "2.5", "1000" }) do
        local q, why = Browse.query({ minLevel = bad })
        assert.is_nil(q, bad)
        assert.truthy(why:find("whole numbers"))
      end
    end)
  end)

  describe("rows", function()
    local results = {
      { itemKey = { itemID = 1, itemLevel = 30 }, totalQuantity = 3, minPrice = 890 },
      { itemKey = { itemID = 2, itemLevel = 25 }, totalQuantity = 1, minPrice = 0 },
      { totalQuantity = 5, minPrice = 10 },
    }
    local look = {
      info = function(key)
        if key.itemID == 1 then return { name = "Bracers", quality = 2, isCommodity = false } end
      end,
      required = function(id) return id == 1 and 23 or nil end,
      value = function(id) return id == 1 and 1420 or 500 end,
    }

    it("builds a row per result with an item key, with market value and percent", function()
      local rows = Browse.rows(results, look)
      assert.equal(2, #rows)
      local r = rows[1]
      assert.equal("Bracers", r.name)
      assert.equal(2, r.quality)
      assert.equal(23, r.level)
      assert.equal(3, r.listed)
      assert.equal(890, r.lowest)
      assert.equal(1420, r.value)
      assert.equal(63, r.percent)
    end)

    it("leaves names, levels and prices it doesn't know empty", function()
      local r = Browse.rows(results, look)[2]
      assert.is_nil(r.name)
      assert.is_nil(r.level)
      assert.is_nil(r.lowest, "a bid-only result has no buyout")
      assert.is_nil(r.percent)
      assert.equal(1, #Browse.rows({ results[1] }), "no lookups needed")
    end)
  end)

  describe("sort", function()
    local function rows()
      return {
        { itemID = 3, itemKey = {}, name = "Cloak", lowest = 500, level = 20 },
        { itemID = 1, itemKey = {}, name = "axe", lowest = 900 },
        { itemID = 2, itemKey = {}, name = nil, lowest = 500, level = 10 },
        { itemID = 4, itemKey = {}, name = "Boots", lowest = nil, level = 30 },
      }
    end
    local function ids(list) local out = {} for i, r in ipairs(list) do out[i] = r.itemID end return out end

    it("sorts low to high, ties by name, missing values last", function()
      assert.same({ 3, 2, 1, 4 }, ids(Browse.sort(rows(), "lowest")))
    end)

    it("sorts high to low with missing values still last", function()
      assert.same({ 1, 3, 2, 4 }, ids(Browse.sort(rows(), "lowest", true)))
      assert.same({ 4, 3, 2, 1 }, ids(Browse.sort(rows(), "level", true)))
    end)

    it("sorts names A to Z ignoring case, unknown names last", function()
      assert.same({ 1, 4, 3, 2 }, ids(Browse.sort(rows(), "name")))
    end)

    it("falls back to the lowest buyout for an unknown column", function()
      assert.same({ 3, 2, 1, 4 }, ids(Browse.sort(rows(), "nonsense")))
    end)

    it("flips a column clicked twice and starts a new one low to high", function()
      assert.same({ "lowest", true }, { Browse.click("lowest", "lowest", false) })
      assert.same({ "name", false }, { Browse.click("name", "lowest", true) })
    end)
  end)

  it("tells cheap and dear prices from fair ones", function()
    assert.equal("cheap", Browse.tone(85))
    assert.is_nil(Browse.tone(100))
    assert.equal("dear", Browse.tone(110))
    assert.is_nil(Browse.tone(nil))
    assert.is_nil(Browse.percent(100, nil))
  end)

  it("sums up a search", function()
    assert.equal('212 items for "linen", level 21-30',
      Browse.summary(212, { searchString = "linen", minLevel = 21, maxLevel = 30 }))
    assert.equal("1 item up to level 10", Browse.summary(1, { searchString = "", minLevel = 0, maxLevel = 10 }))
    assert.equal("3 items level 5 and up", Browse.summary(3, { searchString = "", minLevel = 5, maxLevel = 0 }))
    assert.truthy(Browse.summary(5, { searchString = "", minLevel = 0, maxLevel = 0 }, true):find("first ones only"))
  end)

  describe("history panel layout", function()
    it("keeps a dragged or saved width in range, and starts at the default", function()
      assert.equal(Browse.HISTORY_WIDTH, Browse.historyWidth(nil))
      assert.equal(Browse.HISTORY_WIDTH, Browse.historyWidth("junk"))
      assert.equal(Browse.HISTORY_WIDTH, Browse.historyWidth(0 / 0))
      assert.equal(Browse.HISTORY_MIN, Browse.historyWidth(10))
      assert.equal(Browse.HISTORY_MAX, Browse.historyWidth(9000))
      assert.equal(201, Browse.historyWidth(200.6))
    end)

    it("gives the item name what the number columns leave, ending inside the table", function()
      for _, width in ipairs({ 430, 558, 700 }) do
        local cols = Browse.columns(width)
        assert.equal(6, #cols)
        assert.equal("Item", cols[1][1])
        assert.equal("name", cols[1][5])
        local last = cols[#cols]
        assert.equal("percent", last[5])
        assert.equal(width - 4, last[2] + last[3], "the last column ends at the right edge")
        for i = 2, #cols do assert.equal(cols[i - 1][2] + cols[i - 1][3] + Browse.COLUMN_GAP, cols[i][2]) end
      end
      assert.equal(60, Browse.columns(100)[1][3], "never narrower than a short name")
    end)
  end)
end)
