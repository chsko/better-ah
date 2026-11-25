local helper = require("spec.helper")
local fake = require("spec.fake_client")

local function setup(opts)
  local env = fake.new(opts)
  local ns = helper.load("BetterAH/Core/Time.lua")
  for _, file in ipairs({ "CharacterRecords", "SelfTest", "Probes" }) do
    helper.load("BetterAH/Core/" .. file .. ".lua", ns)
  end
  helper.load("BetterAH/Game/CharacterTracker.lua", ns)
  ns.characters = ns.CharacterRecords.new({})
  local tracker = ns.CharacterTracker.install(env, ns)
  return env, tracker, ns
end

local function slots(...)
  local out = {}
  for i, it in ipairs({ ... }) do out[i] = it end
  return out
end

describe("CharacterTracker", function()
  it("keys characters by name and server, so namesakes on other rulesets stay apart", function()
    local env, _, ns = setup()
    assert.equal("Thrall-6841", ns.CharacterTracker.characterKey(env))
    env.guid = nil
    assert.is_nil(ns.CharacterTracker.characterKey(env), "never stored twice, under the bare name too")
  end)

  it("records the bags when the player logs in and whenever they change", function()
    local env, _, ns = setup()
    env.containers[0] = slots({ itemID = 2589, count = 20, name = "Linen Cloth" }, false,
      { itemID = 2589, count = 5, name = "Linen Cloth" })
    env.containers[1] = slots({ itemID = 2592, count = 3, name = "Wool Cloth" })
    env.fire("PLAYER_ENTERING_WORLD")
    assert.same({
      { item = "i:2589", name = "Linen Cloth", total = 25, characters = 1 },
      { item = "i:2592", name = "Wool Cloth", total = 3, characters = 1 },
    }, ns.characters:items())
    env.containers[1] = {}
    env.fire("BAG_UPDATE_DELAYED")
    assert.equal(0, (ns.characters:count("i:2592")))
    local chars = ns.characters:characters()
    assert.same({ "Thrall-6841", "Thrall", "Horde" }, { chars[1].key, chars[1].name, chars[1].faction })
  end)

  it("reads the bank tabs only while the bank is open, and follows deposits", function()
    local env, _, ns = setup()
    env.containers[-2] = slots({ itemID = 4500, count = 1 })
    env.containers[6] = slots({ itemID = 2589, count = 40 }, false)
    env.containers[7] = slots({ itemID = 2592, count = 7 })
    env.fire("BAG_UPDATE_DELAYED")
    assert.equal(0, (ns.characters:count("i:2589")), "bank closed: nothing read")
    env.fire("BANKFRAME_OPENED")
    local _, by = ns.characters:count("i:2589")
    assert.equal(40, by[1].bank)
    assert.equal(0, (ns.characters:count("i:4500")), "the bank's own bags are not bank contents")
    env.containers[6][2] = { itemID = 2592, count = 3 }
    env.fire("BAG_UPDATE_DELAYED")
    assert.equal(10, (ns.characters:count("i:2592")), "a deposit shows while the bank is still open")
    env.fire("BANKFRAME_CLOSED")
    env.containers[6], env.containers[7] = {}, {}
    env.fire("BAG_UPDATE_DELAYED")
    assert.equal(40, (ns.characters:count("i:2589")), "the bank is remembered after closing")
  end)

  it("keeps what it had when the game reports no slots at all", function()
    local env, tracker, ns = setup()
    env.containers[0] = slots({ itemID = 2589, count = 5 })
    env.fire("PLAYER_ENTERING_WORLD")
    env.containers[0] = {}
    assert.is_false(tracker:update("bags"))
    assert.equal(5, (ns.characters:count("i:2589")))
  end)

  it("asks for the player's auctions when the auction house opens and keeps the active ones", function()
    local env, _, ns = setup()
    env.owned = { { itemID = 2589, quantity = 20 }, { itemID = 2592, quantity = 5, status = 1 } }
    env.openAuctionHouse()
    assert.equal(1, env.ownedQueries)
    local _, by = ns.characters:count("i:2589")
    assert.equal(20, by[1].auctions)
    assert.equal(0, (ns.characters:count("i:2592")), "sold auctions are not the player's any more")
  end)

  it("never replaces the auctions with a partial list or with nothing while the auction house is closed", function()
    local env, _, ns = setup()
    env.owned = { { itemID = 2589, quantity = 20 }, { itemID = 2589, quantity = 20 } }
    env.openAuctionHouse()
    assert.equal(40, (ns.characters:count("i:2589")))
    env.owned, env.ownedComplete = { { itemID = 2589, quantity = 20 } }, false
    env.fire("OWNED_AUCTIONS_UPDATED")
    assert.equal(40, (ns.characters:count("i:2589")), "partial result ignored")
    env.ownedComplete = true
    env.CloseAuctionHouse()
    env.owned = {}
    env.fire("OWNED_AUCTIONS_UPDATED")
    assert.equal(40, (ns.characters:count("i:2589")), "closed: ignored")
  end)

  it("asks again for the auctions after posting or cancelling", function()
    local env = setup()
    env.openAuctionHouse()
    env.fire("AUCTION_HOUSE_AUCTION_CREATED")
    env.fire("AUCTION_CANCELED")
    assert.equal(3, env.ownedQueries)
  end)

  it("does nothing before the game says who the player is or before the records exist", function()
    local env, tracker, ns = setup()
    env.playerName = nil
    assert.is_false(tracker:update("bags"))
    env.playerName = "Thrall"
    ns.characters = nil
    assert.is_false(tracker:update("bags"))
  end)

  it("adds self-test checks for the bag and bank functions", function()
    local env, _, ns = setup()
    env.containers[0] = slots({ itemID = 1, count = 2 }, false, false)
    local results = {}
    for _, r in ipairs(ns.Probes.suite():run(env, { db = {} })) do results[r.name] = r end
    assert.same({ "pass", "3 slots, 2 items in 1 stacks" }, { results.Bags.status, results.Bags.detail })
    assert.same({ "info", "bank functions: yes; this character's bank last read: never (open your bank once)" },
      { results.Bank.status, results.Bank.detail })
    env.C_Container = nil
    for _, r in ipairs(ns.Probes.suite():run(env, { db = {} })) do results[r.name] = r end
    assert.equal("fail", results.Bags.status)
  end)
end)
