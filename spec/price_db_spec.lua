local helper = require("spec.helper")

describe("PriceDB", function()
  local PriceDB = helper.load("BetterAH/Core/PriceDB.lua", helper.load("BetterAH/Core/MarketValue.lua")).PriceDB
  local A, B = "/1/Horde", "/1/Alliance"

  local function linen(count, buyout)
    return { item = "i:2589", name = "Linen Cloth", count = count, buyout = buyout }
  end

  it("records the lowest buyout per unit and the quantity for each item", function()
    local db = PriceDB.new({})
    local n = db:recordScan(A, 100, {
      linen(20, 4000), linen(5, 500), { item = "i:2592", name = "Wool Cloth", count = 10, buyout = 3000 },
    })
    assert.equal(2, n)
    assert.same({
      { item = "i:2589", name = "Linen Cloth", lowest = 100, quantity = 25, listings = 2, seen = 100 },
      { item = "i:2592", name = "Wool Cloth", lowest = 300, quantity = 10, listings = 1, seen = 100 },
    }, db:items(A))
    assert.equal(100, db:lastScan(A))
  end)

  it("ignores bid-only listings for the lowest buyout but counts their quantity", function()
    local db = PriceDB.new({})
    db:recordScan(A, 100, { linen(10, 0), linen(1, nil) })
    local item = db:items(A)[1]
    assert.is_nil(item.lowest)
    assert.equal(11, item.quantity)
  end)

  it("skips listings without an item or a count", function()
    local db = PriceDB.new({})
    assert.equal(0, db:recordScan(A, 100, { { name = "?", count = 1, buyout = 5 }, linen(0, 100) }))
    assert.same({}, db:items(A))
  end)

  it("replaces an item's numbers with the newest scan and keeps items it didn't see", function()
    local db = PriceDB.new({})
    db:recordScan(A, 100, { linen(1, 200), { item = "i:2592", name = "Wool Cloth", count = 1, buyout = 300 } })
    db:recordScan(A, 200, { linen(1, 150) })
    local items = db:items(A)
    assert.same({ 150, 200 }, { items[1].lowest, items[1].seen })
    assert.same({ 300, 100 }, { items[2].lowest, items[2].seen })
    assert.equal(200, db:lastScan(A))
  end)

  it("never mixes data from two markets", function()
    local db = PriceDB.new({})
    db:recordScan(A, 100, { linen(1, 200) })
    db:recordScan(B, 150, { linen(1, 900) })
    assert.equal(200, db:items(A)[1].lowest)
    assert.equal(900, db:items(B)[1].lowest)
    assert.equal(100, db:lastScan(A))
    assert.equal(150, db:lastScan(B))
  end)

  it("has nothing for a market never scanned", function()
    local db = PriceDB.new({})
    assert.same({}, db:items(A))
    assert.is_nil(db:lastScan(A))
  end)

  it("keeps its data in the store it was given, so saved variables persist it", function()
    local store = {}
    PriceDB.new(store):recordScan(A, 100, { linen(1, 200) })
    assert.equal(200, PriceDB.new(store):items(A)[1].lowest)
  end)

  it("sorts by name, naming unnamed items with the caller's lookup and putting the rest last", function()
    local db = PriceDB.new({})
    db:recordScan(A, 100, {
      { item = "i:3", count = 1, buyout = 1 },
      { item = "i:1", count = 1, buyout = 1 },
      { item = "i:2", name = "wool Cloth", count = 1, buyout = 1 },
      { item = "i:4", name = "Black Mageweave Robe", count = 1, buyout = 1 },
      { item = "i:5", count = 1, buyout = 1 },
    })
    local names = { ["i:5"] = "Linen Cloth" }
    local order = {}
    for _, it in ipairs(db:items(A, function(item) return names[item] end)) do
      order[#order + 1] = it.name or it.item
    end
    assert.same({ "Black Mageweave Robe", "Linen Cloth", "wool Cloth", "i:1", "i:3" }, order)
  end)

  it("keeps a stored name over the lookup and ignores empty or odd lookups", function()
    local db = PriceDB.new({})
    db:recordScan(A, 100, {
      { item = "i:1", name = "Linen Cloth", count = 1, buyout = 1 },
      { item = "i:2", count = 1, buyout = 1 },
      { item = "i:3", count = 1, buyout = 1 },
      { item = "i:4", name = "linen cloth", count = 1, buyout = 1 },
    })
    local lookup = { ["i:1"] = "Wrong", ["i:2"] = "", ["i:3"] = 42 }
    local order = {}
    for _, it in ipairs(db:items(A, function(item) return lookup[item] end)) do
      order[#order + 1] = it.item .. "=" .. tostring(it.name)
    end
    assert.same({ "i:1=Linen Cloth", "i:4=linen cloth", "i:2=nil", "i:3=nil" }, order)
  end)

  describe("market value and history", function()
    local DAY = 86400
    local t0 = 200 * DAY

    local function wool(unit, n)
      local out = {}
      for i = 1, n or 5 do out[i] = { item = "i:2592", name = "Wool Cloth", count = 1, buyout = unit } end
      return out
    end

    it("keeps one history point per day per market, averaging scans on the same day", function()
      local db = PriceDB.new({})
      db:recordScan(A, t0, wool(100))
      db:recordScan(A, t0 + 3600, wool(300))
      db:recordScan(A, t0 + DAY, wool(200))
      db:recordScan(B, t0, wool(999))
      assert.same({ { day = 200, value = 200, points = 2 }, { day = 201, value = 200, points = 1 } },
        db:history(A, "i:2592"))
      assert.equal(999, db:history(B, "i:2592")[1].value, "the other market has its own history")
    end)

    it("stores history compactly in the saved variables", function()
      local store = {}
      local db = PriceDB.new(store)
      db:recordScan(A, t0, wool(100))
      db:recordScan(A, t0 + DAY, wool(200))
      assert.equal("200:100:1;201:200:1", store[A].items["i:2592"].hist)
      assert.equal("201:5:1:0", store[A].items["i:2592"].scan)
    end)

    it("gives a smoothed market value with what it was based on", function()
      local db = PriceDB.new({})
      db:recordScan(A, t0, wool(100))
      db:recordScan(A, t0 + DAY, wool(200))
      local value, info = db:marketValue(A, "i:2592", t0 + DAY)
      assert.equal(152, value) -- (200 * 14 + 100 * 13) / 27
      assert.same({ days = 2, oldest = 1, scan = { day = 201, units = 5, used = 1, dropped = 0 } }, info)
      assert.is_nil(db:marketValue(A, "i:2592", t0 + 20 * DAY), "too old to say")
      assert.is_nil(db:marketValue(A, "i:1", t0))
      assert.equal(152, db:items(A, nil, t0 + DAY)[1].value)
    end)

    it("keeps 30 days of history", function()
      local db = PriceDB.new({})
      db:recordScan(A, t0, wool(100))
      db:recordScan(A, t0 + 29 * DAY, wool(150))
      assert.equal(2, #db:history(A, "i:2592"))
      db:recordScan(A, t0 + 30 * DAY, wool(200))
      local h = db:history(A, "i:2592")
      assert.same({ 229, 230 }, { h[1].day, h[2].day })
    end)

    it("records a search as a value point from other sellers only, never as a scan", function()
      local db = PriceDB.new({})
      assert.is_true(db:recordSearch(A, t0, "i:2589", { { unit = 10, count = 5 }, { unit = 12.5, count = 2 },
        { unit = 1, count = 30, ownCount = 30 } }, "Linen Cloth"))
      assert.is_nil(db:lastScan(A))
      local items = db:items(A)
      assert.same({ "Linen Cloth", nil, nil }, { items[1].name, items[1].lowest, items[1].seen })
      local value, info = db:marketValue(A, "i:2589", t0)
      assert.equal(10, value, "the player's own cheap units don't count")
      assert.same({ day = 200, units = 7, used = 0, dropped = 0 }, info.search)
      assert.is_false(db:recordSearch(A, t0 + 60, "i:2589", { { unit = 1, count = 5 }, { unit = 2, count = 5 } }),
        "once per item per day")
    end)

    it("needs a few other sellers' units before a search sets a value", function()
      local db = PriceDB.new({})
      assert.is_false(db:recordSearch(A, t0, "i:1", {}))
      assert.is_false(db:recordSearch(A, t0, "i:1", { { unit = 100, count = 1 } }), "a lone listing")
      assert.is_false(db:recordSearch(A, t0, "i:1", { { unit = 100, count = 1 }, { unit = 5000, count = 1 } }),
        "two units: too few for the troll filter")
      assert.is_false(db:recordSearch(A, t0, "i:1", { { unit = 100, count = 9 } }), "one listing, however big")
      assert.is_true(db:recordSearch(A, t0, "i:1", { { unit = 100, count = 1 }, { unit = 5000, count = 2 } }))
      assert.equal(5000, (db:marketValue(A, "i:1", t0)), "the middle price, not the dumped one")
      assert.is_true(db:recordSearch(A, t0, "i:2", { { unit = 1000, count = 1 }, { unit = 5000, count = 2 } }))
      assert.equal(5000, (db:marketValue(A, "i:2", t0)), "a cheap listing can't set the floor that undercuts it")
    end)

    it("leaves a day a full scan saw alone", function()
      local db = PriceDB.new({})
      db:recordScan(A, t0, wool(250))
      assert.is_false(db:recordSearch(A, t0 + 60, "i:2592", { { unit = 1, count = 5 }, { unit = 2, count = 5 } }))
      assert.equal(250, (db:marketValue(A, "i:2592", t0)))
    end)

    it("takes imported prices through the same path as scans", function()
      local db = PriceDB.new({})
      local before = db:version(A)
      assert.equal(2, db:importPrices(A, t0, {
        ["i:2592"] = { value = 150, name = "Wool Cloth" }, ["i:2589"] = { value = 40 }, ["i:1"] = { value = 0 },
        ["i:3"] = { value = 1e15 },
      }))
      assert.is_true(db:version(A) > before)
      assert.is_nil(db:lastScan(A), "an import is not a scan")
      local value, info = db:marketValue(A, "i:2592", t0)
      assert.equal(150, value)
      assert.same({ days = 1, oldest = 0, imported = 200 }, info)
      db:recordScan(A, t0 + 60, wool(250))
      value, info = db:marketValue(A, "i:2592", t0)
      assert.equal(200, value, "a scan on the same day averages with the import")
      assert.same({ 200, 200 }, { info.scan.day, info.imported }, "the detail can mention both")
      local item = db:items(A, nil, t0)[1]
      assert.same({ "Wool Cloth", 250, 5 }, { item.name, item.lowest, item.quantity })
    end)

    it("files a backdated import under its own day, in order", function()
      local db = PriceDB.new({})
      db:recordScan(A, t0 + 5 * DAY, wool(200))
      db:importPrices(A, t0, { ["i:2592"] = { value = 100 } })
      db:importPrices(A, t0 + 3 * DAY, { ["i:2592"] = { value = 150 } })
      local days = {}
      for i, h in ipairs(db:history(A, "i:2592")) do days[i] = h.day end
      assert.same({ 200, 203, 205 }, days)
      local _, info = db:marketValue(A, "i:2592", t0 + 5 * DAY)
      assert.equal(203, info.imported)
      db:importPrices(A, t0 - 40 * DAY, { ["i:2592"] = { value = 1 } })
      assert.equal(3, #db:history(A, "i:2592"), "an import older than the kept history is dropped")
    end)

    it("leaves bid-only items without a market value", function()
      local db = PriceDB.new({})
      db:recordScan(A, t0, { { item = "i:7", count = 1, buyout = 0 } })
      assert.is_nil(db:marketValue(A, "i:7", t0))
      assert.same({}, db:history(A, "i:7"))
    end)
  end)
end)
