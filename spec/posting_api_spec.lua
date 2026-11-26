local helper = require("spec.helper")
local fake = require("spec.fake_client")

local function setup(opts)
  local env = fake.new(opts)
  local ns = helper.load("BetterAH/Core/Posting.lua")
  for _, file in ipairs({ "SelfTest", "Probes" }) do helper.load("BetterAH/Core/" .. file .. ".lua", ns) end
  helper.load("BetterAH/Game/PostingAPI.lua", ns)
  local api = ns.PostingAPI.install(env, ns)
  return env, api, ns
end

local linen = { itemID = 2589, count = 20, name = "Linen Cloth" }
local backpack = { itemID = 4500, count = 1, name = "Traveler's Backpack", item = true }
local post = { action = "post", price = 99, duration = 2, quantity = 20, posts = 1, remainder = 0 }

local function commodity(id) return { itemID = id, itemKey = { itemID = id }, commodity = true } end

describe("PostingAPI", function()
  it("finds the items in the bags the auction house accepts, grouped and sorted by name", function()
    local env, _, ns = setup()
    env.containers[0] = {
      { itemID = 2592, count = 3, name = "Wool Cloth" }, false,
      { itemID = 2589, count = 20, name = "Linen Cloth" },
      { itemID = 6948, count = 1, name = "Hearthstone", soulbound = true },
      { itemID = 2589, count = 5, name = "Linen Cloth" },
      { itemID = 2589, count = 7, name = "Linen Cloth", locked = true },
    }
    env.containers[1] = { { itemID = 1, count = 1, name = "Bound Ring", bound = true }, backpack,
      { itemID = 9, count = 1, name = "Not Loaded", unknown = true } }
    local entries = ns.PostingAPI.readBags(env)
    local summary = {}
    for i, e in ipairs(entries) do summary[i] = { e.item, e.have, #e.slots, e.commodity } end
    assert.same({
      { "i:2589", 25, 2, true }, { "i:4500", 1, 1, false }, { "i:2592", 3, 1, true },
    }, summary, "locked slots and items of unknown kind wait for the next read")
    assert.same({ bag = 0, slot = 3 }, entries[1].slots[1].location)
    assert.same({ itemID = 2589, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }, entries[1].itemKey)
  end)

  it("keeps an item's kind from an earlier read while its data loads again (#82)", function()
    local env, _, ns = setup()
    local asked = {}
    env.C_Item = { RequestLoadItemDataByID = function(id) asked[#asked + 1] = id end }
    env.containers[0] = { { itemID = 9, count = 2, name = "Not Loaded", unknown = true },
      { itemID = 9, count = 3, name = "Not Loaded", unknown = true } }
    local once = {}
    assert.same({}, ns.PostingAPI.readBags(env, {}, once))
    assert.same({}, ns.PostingAPI.readBags(env, {}, once))
    assert.same({ 9 }, asked, "asked once, not per slot or per read")
    local entries = ns.PostingAPI.readBags(env, { ["i:9"] = true })
    assert.equal(1, #entries)
    assert.equal(5, entries[1].have)
    assert.is_true(entries[1].commodity)
    -- Also when the client says it can't be sold while its data is gone.
    for _, it in ipairs(env.containers[0]) do it.unknown, it.unsellable = nil, true end
    assert.equal(1, #ns.PostingAPI.readBags(env, { ["i:9"] = true }))
    assert.same({}, ns.PostingAPI.readBags(env, {}), "but not an item never seen sellable")
    assert.matches("Not Loaded x2: not sellable", table.concat(ns.PostingAPI.slotReport(env), "\n"), 1, true)
  end)

  it("says what is missing on a client without the functions", function()
    local env, _, ns = setup()
    env.ItemLocation = nil
    local entries, why = ns.PostingAPI.readBags(env)
    assert.is_nil(entries)
    assert.matches("ItemLocation", why)
  end)

  it("tells Posting.plan to use whole silver when the client has no copper values", function()
    local env, _, ns = setup()
    assert.equal(1, ns.PostingAPI.priceStep(env))
    env.copperValues = false
    assert.equal(100, ns.PostingAPI.priceStep(env))
  end)

  it("searches one item at a time, cheapest first with own listings apart, and reads the rows", function()
    local env, api, ns = setup()
    env.containers[0] = { linen, backpack }
    env.listings[2589] = { { unitPrice = 95, quantity = 40, numOwnerItems = 20 }, { unitPrice = 100, quantity = 5 } }
    env.listings[4500] = { item = true, { buyoutAmount = 50000, quantity = 2 },
      { buyoutAmount = 40000, quantity = 1, containsOwnerItem = true } }
    env.openAuctionHouse()
    local got = {}
    for _, e in ipairs(ns.PostingAPI.readBags(env)) do
      api:search(e, function(listings, complete) got[#got + 1] = { e.item, listings, complete } end)
    end
    assert.equal(1, #env.searches, "the second waits for the first")
    assert.same({ { sortOrder = 0, reverseSort = false } }, env.searches[1].sorts)
    assert.is_true(env.searches[1].separate)
    env.runTimers()
    assert.equal(2, #env.searches)
    assert.same({
      { "i:2589", { { unit = 95, count = 40, ownCount = 20 }, { unit = 100, count = 5, ownCount = 0 } }, true },
      { "i:4500", { { unit = 50000, count = 2, ownCount = 0 }, { unit = 40000, count = 1, ownCount = 1 } }, true },
    }, got, "an item's buyout is per item")
  end)

  it("puts a search the player waits on ahead of the background ones, newest first (#122)", function()
    local env, api = setup()
    env.openAuctionHouse()
    local order = {}
    local function job(id, first)
      api:search(commodity(id), function() order[#order + 1] = id end, first)
    end
    job(1) job(2) job(3)
    job(10, true) job(11, true)
    env.runTimers(1)
    env.runTimers(1)
    env.runTimers(1)
    env.runTimers(1)
    env.runTimers(1)
    assert.same({ 1, 11, 10, 2, 3 }, order, "the one already sent finishes, then the player's newest, then the rest")
  end)

  it("says when the client has only part of the results", function()
    local env, api = setup()
    env.openAuctionHouse()
    env.fullResults = false
    local complete
    api:search(commodity(1), function(_, c) complete = c end)
    env.runTimers()
    assert.is_false(complete)
  end)

  it("ignores results for another item while a search is running", function()
    local env, api = setup()
    env.openAuctionHouse()
    env.searchSilent = true
    local result
    api:search({ itemID = 4500, itemKey = { itemID = 4500 }, commodity = false }, function(l) result = l end)
    env.fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 1 })
    env.fire("COMMODITY_SEARCH_RESULTS_UPDATED", 4500)
    assert.is_nil(result)
    env.fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 4500, itemLevel = 0 })
    assert.same({}, result, "matched on the item even with a cleared item level")
  end)

  it("waits for the throttle before sending a search", function()
    local env, api = setup()
    env.openAuctionHouse()
    env.throttled = true
    local result
    api:search(commodity(1), function(l) result = l end)
    assert.equal(0, #env.searches)
    env.throttled = false
    env.fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    env.runTimers()
    assert.equal(1, #env.searches)
    assert.same({}, result)
  end)

  it("gives up on a search with no answer, and a late timeout never ends the next one", function()
    local env, api = setup()
    env.openAuctionHouse()
    env.searchSilent = true
    local results = {}
    api:search(commodity(1), function(l, why) results[1] = { l, why } end)
    env.runTimers(5)
    api:search(commodity(2), function(l, why) results[2] = { l, why } end)
    env.runTimers(5)
    assert.same({ nil, "no answer from the auction house" }, results[1])
    assert.is_nil(results[2], "the second started at 10s and has its own 10s")
    env.runTimers(10)
    assert.same({ nil, "no answer from the auction house" }, results[2])
  end)

  it("keeps going when a caller's callback fails or searches again", function()
    local env, api = setup()
    env.openAuctionHouse()
    env.geterrorhandler = function() return function() end end
    local order = {}
    api:search(commodity(1), function()
      order[#order + 1] = 1
      api:search(commodity(3), function() order[#order + 1] = 3 end)
      error("boom")
    end)
    api:search(commodity(2), function() order[#order + 1] = 2 end)
    env.runTimers()
    assert.same({ 1, 2, 3 }, order)
  end)

  it("ends waiting searches when the auction house closes and refuses new ones until it opens", function()
    local env, api = setup()
    env.openAuctionHouse()
    env.searchSilent = true
    local reasons = {}
    for i = 1, 2 do api:search(commodity(i), function(_, why) reasons[i] = why end) end
    env.CloseAuctionHouse()
    assert.same({ "the auction house closed", "the auction house closed" }, reasons)
    api:search(commodity(3), function(_, why) reasons[3] = why end)
    assert.equal("the auction house is closed", reasons[3])
    assert.equal(1, #env.searches)
  end)

  it("posts a commodity, and an item from one slot, at the planned unit price", function()
    local env, api, ns = setup()
    env.containers[0] = { linen, backpack }
    local entries = ns.PostingAPI.readBags(env)
    assert.equal("sent", api:post(entries[1], post))
    assert.equal("sent", api:post(entries[2], { action = "post", price = 45000, duration = 3, quantity = 5 }))
    assert.same({
      { kind = "commodity", loc = { bag = 0, slot = 1 }, duration = 2, quantity = 20, price = 99 },
      { kind = "item", loc = { bag = 0, slot = 2 }, duration = 3, quantity = 1, price = 45000 },
    }, env.posts)
  end)

  it("never posts from a slot that no longer holds the item", function()
    local env, api, ns = setup()
    env.containers[0] = { linen, { itemID = 2589, count = 5, name = "Linen Cloth" } }
    local entry = ns.PostingAPI.readBags(env)[1]
    env.containers[0][1] = { itemID = 13468, count = 20, name = "Black Lotus" }
    assert.equal("sent", api:post(entry, post))
    assert.same({ bag = 0, slot = 2 }, env.posts[1].loc, "the next slot that still holds it")
    env.containers[0][2] = { itemID = 2589, count = 5, name = "Linen Cloth", locked = true }
    assert.same({ nil, "your bags changed; the list will update" }, { api:post(entry, post) })
    assert.equal(1, #env.posts)
  end)

  it("doesn't post while the auction house is busy", function()
    local env, api, ns = setup()
    env.containers[0] = { linen }
    env.throttled = true
    assert.same({ nil, "the auction house is busy; try again in a moment" },
      { api:post(ns.PostingAPI.readBags(env)[1], post) })
  end)

  it("asks for a second click when the client wants the post confirmed", function()
    local env, api, ns = setup()
    env.containers[0] = { linen }
    env.needsConfirmation = true
    local warned = false
    api.onPostWarning = function() warned = true end
    local entry = ns.PostingAPI.readBags(env)[1]
    assert.equal("confirm", api:post(entry, post))
    env.runTimers()
    assert.is_true(warned)
    assert.equal("sent", api:confirm())
    assert.same({ kind = "confirm commodity", loc = { bag = 0, slot = 1 }, duration = 2, quantity = 20, price = 99 },
      env.posts[2])
    assert.same({ nil, "nothing to confirm" }, { api:confirm() })
  end)

  it("won't confirm after the bags changed, the post finished or the auction house closed", function()
    local env, api, ns = setup()
    env.containers[0] = { linen }
    env.needsConfirmation = true
    local entry = ns.PostingAPI.readBags(env)[1]
    api:post(entry, post)
    env.containers[0][1] = { itemID = 13468, count = 20 }
    assert.same({ nil, "your bags changed; the list will update" }, { api:confirm() })
    env.containers[0][1] = linen
    for _, event in ipairs({ "AUCTION_HOUSE_POST_ERROR", "AUCTION_HOUSE_CLOSED" }) do
      api:post(entry, post)
      env.fire(event)
      assert.same({ nil, "nothing to confirm" }, { api:confirm() }, event)
    end
  end)

  it("refuses to post without a post plan", function()
    local env, api, ns = setup()
    env.containers[0] = { linen }
    assert.same({ nil, "nothing to post" }, { api:post(ns.PostingAPI.readBags(env)[1], { action = "skip" }) })
    assert.equal(0, #env.posts)
  end)

  it("tells the caller when a post went through or failed", function()
    local env, api = setup()
    local seen = {}
    api.onPosted = function(ok, err) seen[#seen + 1] = { ok, err } end
    env.fire("AUCTION_HOUSE_AUCTION_CREATED", 1)
    env.fire("AUCTION_HOUSE_POST_ERROR")
    env.fire("AUCTION_HOUSE_SHOW_ERROR", 2)
    assert.same({ { true }, { false }, { false, 2 } }, seen)
  end)

  it("adds a self-test check for the posting functions, without posting", function()
    local env, _, ns = setup()
    env.containers[0] = { linen, backpack }
    local function check()
      for _, res in ipairs(ns.Probes.suite():run(env, { db = {} })) do
        if res.name == "Posting API" then return { res.status, res.detail } end
      end
    end
    assert.same({ "pass", "2 items in your bags can be posted (1 commodities, 1 items); copper prices: yes" }, check())
    env.copperValues = false
    assert.matches("copper prices: no, prices go in whole silver", check()[2])
    assert.equal(0, #env.posts)
    env.C_AuctionHouse.ConfirmPostItem = nil
    assert.same({ "fail", "missing: C_AuctionHouse.ConfirmPostItem" }, check())
  end)
end)
