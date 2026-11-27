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
    return nil, nil, m.sender, m.subject, m.money, nil, m.daysLeft, m.item and 1 or nil
  end
  env.GetInboxInvoiceInfo = function(i)
    local m = env.mails[i]
    return m.kind, m.name, nil, m.bid, m.buyout, m.deposit, m.cut, nil, nil, nil, m.count
  end
  -- Taking asks the server; serve() is the server carrying it out: what was taken goes from the mail, and a
  -- mail left empty is deleted. env.asked lists what was asked for since the last serve().
  env.asked = {}
  local function ask(what) return function(i) env.asked[#env.asked + 1] = { i = i, what = what } end end
  env.TakeInboxMoney, env.TakeInboxItem, env.AutoLootMailItem = ask("money"), ask("item"), ask("all")
  env.serve = function(keepEmpty)
    local done = {}
    for _, a in ipairs(env.asked) do
      local m = env.mails[a.i]
      if m then
        if a.what ~= "item" then m.money = 0 end
        if a.what ~= "money" then m.item = nil end
        if not keepEmpty and m.money == 0 and not m.item then done[m] = true end
      end
    end
    env.asked = {}
    local left = {}
    for _, m in ipairs(env.mails) do if not done[m] then left[#left + 1] = m end end
    env.mails = left
  end
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
    local function buyer(over)
      local m = { kind = "buyer", name = "Thorium Bar", sender = "Auction House", subject = "Auction won",
        money = 0, bid = 72000, buyout = 72000, count = 20, daysLeft = 30, item = true }
      for k, v in pairs(over or {}) do m[k] = v end
      return m
    end
    local function update() api:onEvent("MAIL_INBOX_UPDATE") end

    it("notes the sale gold waiting in the inbox", function()
      env.mails = { sale(), sale({ money = 100, daysLeft = 29.5 }), { kind = nil, money = 5 } }
      update()
      assert.same({ 3675, 2, 1000 }, { addon.ledger:inMail("Me") })
    end)

    it("records a sale once the server has taken its gold, and only once", function()
      env.mails = { sale() }
      api:onEvent("MAIL_SHOW")
      env.TakeInboxMoney(1)
      env.AutoLootMailItem(1)
      assert.equal(0, #entries(), "only asked so far")
      env.serve()
      update()
      assert.equal(1, #entries())
      local e = entries()[1]
      assert.equal("sale", e.k)
      assert.equal(3700, e.c)
      assert.equal(185, e.cut)
      assert.equal(60, e.dep)
      assert.equal(20, e.n)
      assert.equal("Me", e.char)
      update()
      assert.equal(1, #entries())
    end)

    it("counts identical sales in different mails", function()
      env.mails = { sale(), sale(), sale() }
      update()
      env.TakeInboxMoney(1)
      env.TakeInboxMoney(2)
      env.serve()
      update()
      assert.equal(2, #entries())
      -- The third moved up to place 1.
      env.AutoLootMailItem(1)
      env.serve()
      update()
      assert.equal(3, #entries())
    end)

    it("counts a mail asked for again and again, while it is still there, once (#150)", function()
      env.mails = { buyer(), buyer(), buyer({ name = "Runecloth", bid = 400, count = 10 }) }
      update()
      -- Open All asks for place 1, the inbox moves for an unrelated reason, it asks again.
      env.TakeInboxItem(1, 1)
      update()
      env.TakeInboxItem(1, 1)
      env.AutoLootMailItem(1)
      env.serve()
      update()
      assert.equal(1, #entries())
      -- The next mail at place 1 is asked for twice across an update in which nothing happened.
      env.TakeInboxItem(1, 1)
      update()
      env.TakeInboxItem(1, 1)
      env.serve()
      update()
      assert.equal(2, #entries())
    end)

    it("does not count a take the server never carried out", function()
      env.mails = { buyer() }
      update()
      env.TakeInboxItem(1, 1)
      env.asked = {} -- the take failed (bags full)
      update()
      env.time = env.time + LedgerAPI.TAKE_WAIT + 1
      update()
      env.mails[#env.mails + 1] = buyer({ name = "Other" })
      table.remove(env.mails, 1) -- later the mail goes some other way: not the old take
      update()
      assert.equal(0, #entries())
    end)

    it("counts a take whose mail is emptied but not deleted, once", function()
      env.mails = { sale(), sale({ name = "Other" }) }
      update()
      env.TakeInboxMoney(1)
      env.serve(true) -- emptied, still there
      update()
      assert.equal(1, #entries())
      table.remove(env.mails, 1) -- deleted later
      update()
      assert.equal(1, #entries())
    end)

    it("does not book a failed take when another mail goes (#150)", function()
      env.mails = { buyer(), { kind = nil, money = 500, sender = "Alt" }, sale() }
      update()
      env.AutoLootMailItem(1) -- bags full: fails
      env.asked = {}
      env.TakeInboxMoney(2) -- the alt's gold: not an invoice
      env.serve()
      update()
      env.TakeInboxMoney(2) -- the sale, now at place 2
      env.serve()
      update()
      assert.equal(1, #entries())
      assert.equal("sale", entries()[1].k)
    end)

    it("counts a take while other mail arrives", function()
      env.mails = { buyer(), buyer(), buyer() }
      update()
      env.TakeInboxItem(1, 1)
      env.serve()
      env.mails[#env.mails + 1] = sale() -- arrived with the same refresh
      update()
      assert.equal(1, #entries())
    end)

    it("counts identical mails taken one after another from the top", function()
      env.mails = { buyer(), buyer(), buyer(), buyer(), buyer() }
      update()
      for _ = 1, 3 do
        env.AutoLootMailItem(1)
        env.AutoLootMailItem(1) -- asked twice
        env.serve()
        update()
      end
      assert.equal(3, #entries())
    end)

    it("reads the mail a take is for as the client has it now", function()
      env.mails = { sale(), buyer({ name = "Runecloth", bid = 400, count = 10 }) }
      update()
      env.TakeInboxMoney(1)
      env.serve()
      -- Another addon takes the next mail on the update, before our read of it.
      env.AutoLootMailItem(1)
      update()
      assert.equal(1, #entries())
      env.serve()
      update()
      assert.equal(2, #entries())
      assert.equal("buy", entries()[2].k)
    end)

    it("does not count waiting takes when the mailbox closes and empties", function()
      env.mails = { buyer() }
      update()
      env.TakeInboxItem(1, 1)
      env.asked = {}
      api:onEvent("MAIL_CLOSED")
      env.mails = {}
      update()
      assert.equal(0, #entries())
    end)

    it("forgets takes waiting from an earlier visit to the mailbox", function()
      env.mails = { buyer(), buyer() }
      api:onEvent("MAIL_SHOW")
      env.TakeInboxItem(1, 1)
      env.asked = {} -- closed before anything happened
      env.mails = { buyer() } -- one expired meanwhile
      api:onEvent("MAIL_SHOW")
      update()
      assert.equal(0, #entries())
    end)

    it("reads a mail it had not seen when it is taken", function()
      env.mails = { sale() }
      env.AutoLootMailItem(1)
      env.serve()
      update()
      assert.equal(1, #entries())
    end)

    it("ignores a take with nothing of that kind in the mail", function()
      env.mails = { sale() }
      update()
      env.TakeInboxItem(1, 1)
      env.serve()
      update()
      assert.equal(0, #entries())
      env.mails = { buyer() }
      update()
      env.TakeInboxMoney(1)
      update()
      assert.equal(0, #entries())
    end)

    it("takes a buyer invoice's item as a buy, unless Better AH made it", function()
      local link = "|cff1eff00|Hitem:12359::::::::60:::::|h[Thorium Bar]|h|r"
      api:bought(12359, link, 20, 72000, "Browse")
      env.mails = { buyer(), buyer({ name = "Runecloth", bid = 400, buyout = 0, count = 10 }) }
      update()
      env.TakeInboxItem(1, 1)
      env.serve()
      update()
      assert.equal(1, #entries(), "the invoice of the Browse buy")
      assert.equal("Thorium Bar", entries()[1].name)
      env.AutoLootMailItem(1)
      env.serve()
      update()
      assert.equal(2, #entries())
      assert.equal("mail", entries()[2].src)
      assert.equal(400, entries()[2].c)
    end)

    it("tells the view when a take is recorded", function()
      local told = 0
      api.onChange = function() told = told + 1 end
      env.mails = { sale() }
      update()
      env.TakeInboxMoney(1)
      env.serve()
      update()
      assert.equal(1, told)
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
