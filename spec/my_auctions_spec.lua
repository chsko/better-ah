local helper = require("spec.helper")
local MyAuctions = helper.load("BetterAH/Core/MyAuctions.lua").MyAuctions

local function auction(fields)
  local a = { id = 1, item = "i:1", key = "1:0:0", name = "Arcane Dust", quantity = 20, unit = 185, timeLeft = 86400 }
  for k, v in pairs(fields or {}) do a[k] = v end
  return a
end

local function found(listings) return { listings = listings, at = 100 } end

describe("MyAuctions.row", function()
  it("marks an auction undercut when someone else lists it cheaper, with how much and how many", function()
    local row = MyAuctions.row(auction(), found({
      { unit = 179, count = 100 }, { unit = 180, count = 40 }, { unit = 185, count = 20, ownCount = 20 },
      { unit = 190, count = 5 },
    }))
    assert.equal("undercut", row.kind)
    assert.equal(179, row.cheapest)
    assert.equal(6, row.by)
    assert.equal(140, row.cheaper, "units below your price; your own and dearer ones don't count")
  end)

  it("ignores your own units, even mixed into another seller's row at the same price", function()
    local row = MyAuctions.row(auction(), found({ { unit = 180, count = 20, ownCount = 20 }, { unit = 185, count = 30,
      ownCount = 20 } }))
    assert.equal("lowest", row.kind)
    assert.equal(185, row.cheapest, "the other seller at your price ties, it doesn't undercut")
  end)

  it("says lowest with no other seller at all", function()
    local row = MyAuctions.row(auction(), found({ { unit = 185, count = 20, ownCount = 20 } }))
    assert.equal("lowest", row.kind)
    assert.is_nil(row.cheapest)
  end)

  it("rounds a fractional undercut up to whole copper", function()
    local row = MyAuctions.row(auction({ unit = 10 }), found({ { unit = 9.5, count = 1 } }))
    assert.equal(1, row.by)
  end)

  it("tells sold, bid, no buyout, unchecked, checking and failed apart", function()
    assert.equal("sold", MyAuctions.row(auction({ sold = true }), found({ { unit = 1, count = 1 } })).kind)
    local bid = MyAuctions.row(auction({ bidder = true, bid = 150 }), found({ { unit = 100, count = 1 } }))
    assert.equal("bid", bid.kind)
    assert.equal(85, bid.by, "a bid auction still says it was undercut")
    assert.equal("nobuyout", MyAuctions.row(auction({ unit = false }), found({})).kind)
    assert.equal("unchecked", MyAuctions.row(auction(), nil).kind)
    assert.equal("checking", MyAuctions.row(auction(), { pending = true }).kind)
    local failed = MyAuctions.row(auction(), { failed = "no answer" })
    assert.equal("failed", failed.kind)
    assert.equal("no answer", failed.reason)
  end)
end)

describe("MyAuctions.rows", function()
  it("sorts undercut first and sold last, then by name and price", function()
    local auctions = {
      auction({ id = 1, name = "Thorium Bar", key = "a", unit = 100 }),
      auction({ id = 2, name = "Runecloth", key = "b", unit = 42 }),
      auction({ id = 3, name = "Arcane Dust", key = "c", sold = true }),
      auction({ id = 4, name = "Arcane Dust", key = "d", unit = 185 }),
      auction({ id = 5, name = "Battleforge Shoulderpads", key = "e", unit = 1500 }),
    }
    local checks = {
      a = found({}), b = found({ { unit = 40, count = 10 } }), d = found({ { unit = 179, count = 3 } }),
      e = { pending = true },
    }
    local ids = {}
    for _, r in ipairs(MyAuctions.rows(auctions, checks)) do ids[#ids + 1] = r.auction.id end
    assert.same({ 4, 2, 5, 1, 3 }, ids)
  end)
end)

describe("MyAuctions filters and counts", function()
  it("counts and filters all, undercut, lowest and sold", function()
    local rows = MyAuctions.rows({
      auction({ id = 1, key = "a" }), auction({ id = 2, key = "b" }), auction({ id = 3, key = "c", sold = true }),
      auction({ id = 4, key = "d" }),
    }, { a = found({ { unit = 100, count = 1 } }), b = found({}) })
    assert.same({ all = 4, undercut = 1, lowest = 1, sold = 1 }, MyAuctions.counts(rows))
    assert.equal(1, #MyAuctions.filter(rows, "undercut"))
    assert.equal(4, #MyAuctions.filter(rows, "all"))
    assert.equal(3, MyAuctions.filter(rows, "sold")[1].auction.id)
  end)
end)

describe("MyAuctions.totals", function()
  it("adds up what is listed, what market value says, what a sale nets and what is on its way", function()
    local rows = MyAuctions.rows({
      auction({ id = 1, key = "a", item = "i:1", quantity = 20, unit = 185, timeLeft = 3600 }),
      auction({ id = 2, key = "b", item = "i:2", quantity = 1, unit = 1500, timeLeft = false, band = 3 }),
      auction({ id = 3, key = "c", item = "i:3", quantity = 2, unit = 11000, sold = true }),
    }, { a = found({ { unit = 179, count = 5 } }) })
    local values = { ["i:1"] = 182 }
    local t = MyAuctions.totals(rows, function(item) return values[item] end, function(a) return a.id * 10 end)
    assert.equal(2, t.active)
    assert.equal(21, t.units)
    assert.equal(20 * 185 + 1500, t.atYours)
    assert.equal(20 * 182, t.atMarket)
    assert.equal(1, t.unpriced)
    assert.equal(MyAuctions.net(3700) + MyAuctions.net(1500), t.afterCut)
    assert.equal(1, t.soon, "one hour left counts, a >12 h band doesn't")
    assert.equal(1, t.sold)
    assert.equal(20900, t.soldGold, "22000 after the 5% cut")
    assert.equal(1, t.undercut)
    assert.equal(10, t.undercutCost)
  end)

  it("counts a short time band as ending soon when the client gives no seconds", function()
    local rows = MyAuctions.rows({ auction({ timeLeft = false, band = 1 }) }, {})
    assert.equal(1, MyAuctions.totals(rows).soon)
  end)
end)

describe("MyAuctions.nextUndercut and toCheck", function()
  it("picks the first undercut row not already being cancelled", function()
    local rows = MyAuctions.rows({ auction({ id = 1, key = "a", name = "A" }),
      auction({ id = 2, key = "a", name = "B" }) }, { a = found({ { unit = 1, count = 1 } }) })
    assert.equal(1, MyAuctions.nextUndercut(rows).auction.id)
    assert.equal(2, MyAuctions.nextUndercut(rows, { [1] = "sent" }).auction.id)
    assert.is_nil(MyAuctions.nextUndercut(rows, { [1] = "sent", [2] = "sent" }))
  end)

  it("checks each item once and skips sold auctions", function()
    local todo = MyAuctions.toCheck({ auction({ id = 1, key = "a" }), auction({ id = 2, key = "a" }),
      auction({ id = 3, key = "b", sold = true }), auction({ id = 4, key = "c" }) })
    assert.equal(2, #todo)
    assert.equal(1, todo[1].id)
    assert.equal(4, todo[2].id)
  end)
end)

describe("MyAuctions.timeLeft", function()
  it("reads seconds as hours or minutes, else the client's band", function()
    assert.equal("24 h", MyAuctions.timeLeft(86400))
    assert.equal("45 min", MyAuctions.timeLeft(2700))
    assert.equal("1 min", MyAuctions.timeLeft(5))
    assert.equal("< 2 h", MyAuctions.timeLeft(nil, 1))
    assert.equal("", MyAuctions.timeLeft(nil, nil))
  end)
end)
