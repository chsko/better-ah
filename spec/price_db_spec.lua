local helper = require("spec.helper")

describe("PriceDB", function()
  local PriceDB = helper.load("BetterAH/Core/PriceDB.lua").PriceDB
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
end)
