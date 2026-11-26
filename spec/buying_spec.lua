local helper = require("spec.helper")

describe("Buying", function()
  local ns, Buying
  before_each(function()
    ns = helper.load("BetterAH/Core/Money.lua")
    helper.load("BetterAH/Core/Browse.lua", ns)
    Buying = helper.load("BetterAH/Core/Buying.lua", ns).Buying
  end)

  describe("itemRows", function()
    local results = {
      { auctionID = 3, buyoutAmount = 1500, bidAmount = 1120, minBid = 1180, timeLeft = 2, owners = { "Mirelle" } },
      { auctionID = 1, buyoutAmount = 1250, minBid = 900, timeLeft = 3, owners = { "Grukdar" } },
      { auctionID = 4, minBid = 800, timeLeft = 0, owners = { "Haskel" }, bidder = "Player-1", bidAmount = 750 },
      { auctionID = 2, buyoutAmount = 1750, minBid = 1200, owners = { "Me" }, containsOwnerItem = true },
      { buyoutAmount = 1 },
    }

    it("lists auctions cheapest buyout first, bid-only ones last", function()
      local rows = Buying.itemRows(results, "Player-1", 1505)
      local ids = {}
      for i, r in ipairs(rows) do ids[i] = r.auctionID end
      assert.same({ 1, 3, 2, 4 }, ids)
      assert.equal(83, rows[1].percent)
      assert.equal("Grukdar", rows[1].seller)
    end)

    it("marks your own auctions and the ones you're winning", function()
      local rows = Buying.itemRows(results, "Player-1")
      assert.is_true(rows[3].own)
      assert.is_false(rows[1].own)
      assert.is_true(rows[4].winning)
      assert.is_false(rows[2].winning)
      assert.is_nil(rows[4].buyout)
      assert.equal(750, rows[4].bid)
      assert.is_false(Buying.itemRows(results, nil)[4].winning, "no GUID, never winning")
    end)
  end)

  it("says when a buyout or bid can't go ahead", function()
    local row = { auctionID = 1, buyout = 1250, minBid = 900 }
    assert.is_true(Buying.canBuyout(row, 5000))
    assert.truthy(select(2, Buying.canBuyout(row, 1000)):find("enough gold"))
    assert.truthy(select(2, Buying.canBuyout({ own = true, buyout = 1 })):find("your own"))
    assert.truthy(select(2, Buying.canBuyout({ minBid = 1 })):find("no buyout"))
    assert.truthy(select(2, Buying.canBuyout(nil)):find("Select"))
    assert.is_true(Buying.canBid(row, 900, 5000))
    assert.truthy(select(2, Buying.canBid(row, 899)):find("9s 0c"))
    assert.truthy(select(2, Buying.canBid(row, 1250)):find("buy it out"))
    assert.truthy(select(2, Buying.canBid(row, 1000, 950)):find("enough gold"))
    assert.truthy(select(2, Buying.canBid({ winning = true }, 1)):find("highest bidder"))
    assert.truthy(select(2, Buying.canBid(row, nil)):find("how much"))
  end)

  it("reads and splits gold, silver and copper", function()
    assert.equal(94500, Buying.money("9", "45", ""))
    assert.equal(45, Buying.money("", "", "45"))
    assert.is_nil(Buying.money("1", "100", "0"))
    assert.is_nil(Buying.money("x", "", ""))
    assert.same({ 9, 45, 3 }, { Buying.split(94503) })
  end)

  describe("ladder", function()
    local listings = {
      { unit = 110, count = 20 }, { unit = 98, count = 6 }, { unit = 102, count = 10, ownCount = 2 },
      { unit = 115, count = 5, ownCount = 5 },
    }

    it("buys cheapest first and leaves out your own units", function()
      local l = Buying.ladder(listings, 20, 118)
      assert.equal(34, l.available)
      assert.equal(20, l.quantity)
      assert.equal(6 * 98 + 8 * 102 + 6 * 110, l.total)
      assert.equal(math.floor(l.total / 20 + 0.5), l.average)
      assert.same({ 6, 8, 6 }, { l.rows[1].take, l.rows[2].take, l.rows[3].take })
      assert.equal(14, l.rows[2].running)
      assert.equal(83, l.rows[1].percent)
    end)

    it("clips the quantity to what is for sale", function()
      local l = Buying.ladder(listings, 100)
      assert.equal(34, l.quantity)
      assert.equal(0, Buying.ladder(listings, "").quantity)
      assert.is_nil(Buying.ladder({}, 5).average)
    end)

    it("works out the most money buys", function()
      local rows = Buying.ladder(listings, 0).rows
      assert.equal(34, Buying.affordable(rows, nil))
      assert.equal(6, Buying.affordable(rows, 6 * 98 + 101))
      assert.equal(7, Buying.affordable(rows, 6 * 98 + 102))
    end)
  end)

  it("compares a quote with the shown price", function()
    assert.equal("same", Buying.quote(2000, 2000))
    assert.equal("same", Buying.quote(2000, 1900))
    assert.equal("up", Buying.quote(2000, 2110))
    assert.equal("unavailable", Buying.quote(2000, nil))
    assert.equal("12 - 48 h", Buying.timeLeftText(3))
    assert.equal("-", Buying.timeLeftText(nil))
  end)
end)
