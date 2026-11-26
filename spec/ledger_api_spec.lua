local helper = require("spec.helper")
local ns = helper.load("BetterAH/Core/Ledger.lua")
helper.load("BetterAH/Game/LedgerAPI.lua", ns)
local Ledger, LedgerAPI = ns.Ledger, ns.LedgerAPI
-- The character key, as Game/CharacterTracker.lua gives it.
ns.CharacterTracker = { characterKey = function(env) return env.UnitName("player") end }

-- A fake client: an inbox of mails, the auction house's deposit functions, and hooksecurefunc.
local function fakeEnv()
  local env = { time = 1000, mails = {} }
  env.GetServerTime = function() return env.time end
  env.UnitName = function() return "Me" end
  env.GetInboxNumItems = function() return #env.mails end
  env.GetInboxHeaderInfo = function(i)
    local m = env.mails[i]
    return nil, nil, m.sender, m.subject, m.money, nil, m.daysLeft
  end
  env.GetInboxInvoiceInfo = function(i)
    local m = env.mails[i]
    return m.kind, m.name, nil, m.bid, m.buyout, m.deposit, m.cut, nil, nil, nil, m.count
  end
  env.TakeInboxMoney = function() end
  env.TakeInboxItem = function() end
  env.AutoLootMailItem = function() end
  env.GetItemInfo = function(id) return "Item " .. id end
  env.C_Item = { GetItemID = function(loc) return loc.id end, GetItemName = function(loc) return loc.name end }
  env.C_AuctionHouse = {
    PostItem = function() end, PostCommodity = function() end,
    ConfirmPostItem = function() end, ConfirmPostCommodity = function() end,
    CalculateItemDeposit = function(_, _, q) return 30 * q end,
    CalculateCommodityDeposit = function(_, _, q) return 6 * q end,
  }
  -- hooksecurefunc(name, fn) or hooksecurefunc(table, name, fn): fn runs after the original.
  env.hooksecurefunc = function(a, b, c)
    local t, name, fn = env, a, b
    if type(a) == "table" then t, name, fn = a, b, c end
    local original = t[name]
    t[name] = function(...)
      local r = { original(...) }
      fn(...)
      return unpack(r)
    end
  end
  return env
end

local function sale(over)
  local m = { kind = "seller", name = "Arcane Dust", sender = "Auction House", subject = "Auction successful",
    money = 3575, bid = 3700, buyout = 3700, deposit = 60, cut = 185, count = 20, daysLeft = 29.9 }
  for k, v in pairs(over or {}) do m[k] = v end
  return m
end

describe("LedgerAPI", function()
  local env, addon, api
  before_each(function()
    env = fakeEnv()
    addon = { ledger = Ledger.new({}) }
    api = LedgerAPI.install(env, addon)
  end)

  local function entries() return addon.ledger.store.entries end

  describe("mail", function()
    it("notes the sale gold waiting in the inbox", function()
      env.mails = { sale(), sale({ money = 100, daysLeft = 29.5 }), { kind = nil, money = 5 } }
      api:onEvent("MAIL_INBOX_UPDATE")
      assert.same({ 3675, 2, 1000 }, { addon.ledger:inMail("Me") })
    end)

    it("records a sale once its gold is taken, and only once", function()
      env.mails = { sale() }
      api:onEvent("MAIL_SHOW")
      env.TakeInboxMoney(1)
      env.AutoLootMailItem(1)
      assert.equal(1, #entries())
      local e = entries()[1]
      assert.equal("sale", e.k)
      assert.equal(3700, e.c)
      assert.equal(185, e.cut)
      assert.equal(60, e.dep)
      assert.equal(20, e.n)
      assert.equal("Me", e.char)
    end)

    it("counts identical sales in different mails", function()
      env.mails = { sale(), sale() }
      api:onEvent("MAIL_INBOX_UPDATE")
      env.TakeInboxMoney(1)
      env.TakeInboxMoney(2)
      assert.equal(2, #entries())
      -- The first goes, the second moves up and is taken again from its new place: once more is not counted.
      table.remove(env.mails, 1)
      api:onEvent("MAIL_INBOX_UPDATE")
      env.AutoLootMailItem(1)
      assert.equal(3, #entries(), "a fresh mail at place 1 after the inbox moved")
    end)

    it("keeps a taken mail taken while the server hasn't removed it", function()
      env.mails = { sale() }
      api:onEvent("MAIL_INBOX_UPDATE")
      env.TakeInboxMoney(1)
      api:onEvent("MAIL_INBOX_UPDATE") -- the mail is still there
      env.AutoLootMailItem(1)
      assert.equal(1, #entries())
    end)

    it("reads a mail it had not seen when it is taken", function()
      env.mails = { sale() }
      env.AutoLootMailItem(1)
      assert.equal(1, #entries())
    end)

    it("counts two different sales", function()
      env.mails = { sale(), sale({ daysLeft = 29.8 }) }
      api:onEvent("MAIL_INBOX_UPDATE")
      env.TakeInboxMoney(1)
      env.TakeInboxMoney(2)
      assert.equal(2, #entries())
    end)

    it("takes a buyer invoice's item as a buy, unless Better AH made it", function()
      api:bought(12359, "Thorium Bar", 20, 72000, "Browse")
      env.mails = {
        { kind = "buyer", name = "Thorium Bar", money = 0, bid = 72000, buyout = 72000, count = 20, daysLeft = 30 },
        { kind = "buyer", name = "Runecloth", money = 0, bid = 400, buyout = 0, count = 10, daysLeft = 30 },
      }
      api:onEvent("MAIL_INBOX_UPDATE")
      env.TakeInboxItem(1, 1)
      env.TakeInboxMoney(2) -- no gold in a buyer invoice: nothing
      assert.equal(1, #entries())
      env.AutoLootMailItem(2)
      assert.equal(2, #entries())
      assert.equal("mail", entries()[2].src)
      assert.equal(400, entries()[2].c)
    end)

    it("ignores a seller invoice's item", function()
      env.mails = { sale() }
      env.TakeInboxItem(1, 1)
      assert.equal(0, #entries())
    end)
  end)

  describe("deposits", function()
    it("records a post's deposit once the auction is up", function()
      env.C_AuctionHouse.PostItem({ id = 4251, name = "Hide" }, 3, 1, nil, 500)
      assert.equal(0, #entries())
      api:onEvent("AUCTION_HOUSE_AUCTION_CREATED")
      assert.equal(1, #entries())
      assert.same({ "deposit", "Hide", 4251, 30 }, { entries()[1].k, entries()[1].name, entries()[1].item,
        entries()[1].c })
    end)

    it("counts a post the client asked to confirm once", function()
      local loc = { id = 16204, name = "Illusion Dust" }
      env.C_AuctionHouse.PostCommodity(loc, 3, 20, 1500)
      env.C_AuctionHouse.ConfirmPostCommodity(loc, 3, 20, 1500)
      api:onEvent("AUCTION_HOUSE_AUCTION_CREATED")
      api:onEvent("AUCTION_HOUSE_AUCTION_CREATED")
      assert.equal(1, #entries())
      assert.equal(120, entries()[1].c)
    end)

    it("counts two posts from the same bag slot as two", function()
      local loc = { id = 4251, name = "Hide" }
      env.C_AuctionHouse.PostItem(loc, 3, 5, nil, 500)
      env.C_AuctionHouse.PostItem(loc, 3, 5, nil, 500)
      api:onEvent("AUCTION_HOUSE_AUCTION_CREATED")
      api:onEvent("AUCTION_HOUSE_AUCTION_CREATED")
      assert.equal(2, #entries())
    end)

    it("drops a post that never went up", function()
      env.C_AuctionHouse.PostItem({ id = 1 }, 3, 1, nil, 5)
      env.time = env.time + LedgerAPI.POST_WAIT + 1
      env.C_AuctionHouse.PostItem({ id = 2 }, 3, 1, nil, 5)
      api:onEvent("AUCTION_HOUSE_AUCTION_CREATED")
      assert.equal(1, #entries())
      assert.equal(2, entries()[1].item)
      assert.equal("Item 2", entries()[1].name)
    end)
  end)

  describe("bought", function()
    it("records a Better AH buy with its source", function()
      api:bought(4251, nil, 1, 1480, "Snipe")
      assert.same({ "buy", "Item 4251", 1480, "Snipe" }, { entries()[1].k, entries()[1].name, entries()[1].c,
        entries()[1].src })
      assert.equal(1, #addon.ledger.store.own)
    end)
  end)

  it("tells the view when something was recorded", function()
    local told = 0
    api.onChange = function() told = told + 1 end
    api:bought(1, "X", 1, 5, "Snipe")
    assert.equal(1, told)
  end)
end)
