local helper = require("spec.helper")

describe("MyBids", function()
  local B
  before_each(function() B = helper.load("BetterAH/Core/MyBids.lua").MyBids end)

  local ME, OTHER = "Player-1-AAAA", "Player-1-BBBB"
  local function bids()
    return {
      { id = 1, item = "i:1", name = "Gryphon Mail Belt", band = 2, minBid = 20075, bid = 19500, buyout = 21000,
        bidder = OTHER },
      { id = 2, item = "i:2", name = "Ridgeback Bracers", band = 0, minBid = 790, bid = 750, buyout = 890,
        bidder = ME },
      { id = 3, item = "i:3", name = "Bonelink Wristguards", band = 3, minBid = 315000, bid = 300000,
        buyout = 380000, bidder = ME },
    }
  end

  it("tells highest from outbid by the high bidder's GUID", function()
    assert.equal("highest", B.status({ bidder = ME }, ME))
    assert.equal("outbid", B.status({ bidder = OTHER }, ME))
    assert.equal("outbid", B.status({ bidder = ME }, nil), "without knowing who we are, nothing is ours")
  end)

  it("remembers what was bid while highest, and shows it once outbid", function()
    local store = {}
    local list = bids()
    list[1].bidder = ME
    list[1].bid = 18000
    B.update(store, list, ME, 100, true)
    assert.equal(18000, store[1].bid)
    list = bids()
    B.update(store, list, ME, 200, true)
    assert.equal(18000, store[1].bid, "outbid keeps our amount, not the new bidder's")
    local rows = B.rows(list, store, ME)
    assert.equal(1, rows[1].bid.id, "outbid comes first")
    assert.equal("outbid", rows[1].status)
    assert.equal(18000, rows[1].yours)
    assert.equal(2, rows[2].bid.id, "then the one ending soonest")
    assert.equal(750, rows[2].yours)
  end)

  it("names every remembered auction in the query, most recent first, at most 100", function()
    local store = {}
    for i = 1, 120 do B.placed(store, i, 100, i) end
    local ids = B.ids(store)
    assert.equal(100, #ids)
    assert.equal(120, ids[1])
    B.update(store, {}, ME, 121, false)
    local n = 0
    for _ in pairs(store) do n = n + 1 end
    assert.equal(100, n, "the store keeps at most 100")
  end)

  it("forgets an auction left out of two answers in a row, but not of lists it didn't ask for", function()
    local store = {}
    B.placed(store, 9, 500, 100, "Old")
    B.update(store, {}, ME, 110, false)
    B.update(store, {}, ME, 120, false)
    assert.is_table(store[9], "lists that weren't our query don't count")
    B.update(store, {}, ME, 130, true)
    assert.is_table(store[9])
    B.update(store, {}, ME, 140, true)
    assert.is_nil(store[9])
    B.placed(store, 8, 500, 100)
    B.update(store, {}, ME, 100 + B.MAX_AGE + 1, false)
    assert.is_nil(store[8], "older than any auction lasts")
  end)

  it("adds up what is tied up in the bids still highest", function()
    local store = { [1] = { bid = 18000, at = 0 } }
    local t = B.totals(B.rows(bids(), store, ME))
    assert.same({ count = 3, highest = 2, outbid = 1, tiedUp = 300750 }, t)
  end)

  it("cleans a broken store and words time left", function()
    local s = B.normalize({ [1] = "junk", x = {}, [2] = { bid = "lots" } })
    assert.is_nil(s[1])
    assert.is_nil(s.x)
    assert.is_nil(s[2].bid)
    assert.equal(0, s[2].at)
    assert.same({}, B.normalize(nil))
    assert.equal("under 30 min", B.timeLeft(0))
    assert.equal("12-48 h", B.timeLeft(3))
    assert.equal("", B.timeLeft(nil))
    assert.same({ winning = true, minBid = 5, buyout = nil }, B.buyRow({ status = "highest", bid = { minBid = 5 } }))
  end)
end)
