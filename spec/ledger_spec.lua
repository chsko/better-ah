local helper = require("spec.helper")
local ns = helper.load("BetterAH/Core/Ledger.lua")
local Ledger = ns.Ledger

local DAY = 86400
-- 2026-11-26 12:00 UTC; offset 3600 is UTC+1.
local NOW = 1795694400

describe("Ledger", function()
  local ledger
  before_each(function() ledger = Ledger.new({}) end)

  describe("new", function()
    it("starts over from a broken store", function()
      local l = Ledger.new({ entries = "x", own = 3 })
      assert.same({}, l.store.entries)
      assert.same({}, l.store.own)
      assert.same({}, l.store.mail)
    end)
  end)

  describe("bareName", function()
    it("takes the name out of an item link, and leaves a plain name alone", function()
      local link = "|cff1eff00|Hitem:4251::::::::60:::::|h[Hillman's Shoulders]|h|r"
      assert.equal("Hillman's Shoulders", Ledger.bareName(link))
      assert.equal("Runecloth", Ledger.bareName("Runecloth"))
      assert.is_nil(Ledger.bareName(""))
    end)
  end)

  describe("migrate", function()
    it("drops the mail buys of a version 1 store and makes its links plain names (#150)", function()
      local link = "|cff1eff00|Hitem:5966::::::::60:::::|h[Guardian Gloves]|h|r"
      local store = { entries = {
        { t = NOW, k = "buy", name = link, n = 1, c = 1898, src = "Snipe" },
        { t = NOW + 60, k = "buy", name = "Guardian Gloves", n = 1, c = 1898, src = "mail" },
        { t = NOW, k = "deposit", name = "Soul Dust", n = 5, c = 1 },
      }, own = { { t = NOW, name = link, n = 1, c = 1898 } } }
      local l = Ledger.new(store)
      assert.equal(2, #l.store.entries)
      assert.equal("Guardian Gloves", l.store.entries[1].name)
      assert.equal("Guardian Gloves", l.store.own[1].name)
      assert.equal(Ledger.VERSION, store.v)
      -- Done once: a mail buy recorded after it stays.
      l:buy({ t = NOW, name = "X", c = 5, src = "mail" })
      assert.equal(3, #Ledger.new(store).store.entries)
    end)
  end)

  describe("sale", function()
    it("works out what it sold for from the money taken, the cut and the deposit back", function()
      local e = ledger:sale({ t = NOW, char = "A", name = "Arcane Dust", n = 20, money = 3515 + 60, cut = 185,
        deposit = 60 })
      assert.same({ t = NOW, k = "sale", char = "A", name = "Arcane Dust", n = 20, c = 3700, cut = 185, dep = 60 }, e)
      assert.equal(3515, Ledger.amount(e))
    end)

    it("ignores an invoice with no money", function()
      assert.is_nil(ledger:sale({ t = NOW, name = "X", money = 0 }))
      assert.equal(0, #ledger.store.entries)
    end)
  end)

  describe("buy and buyerInvoice", function()
    it("records a buy as gold out", function()
      local e = ledger:buy({ t = NOW, char = "A", name = "Thorium Bar", item = 12359, n = 20, c = 72000,
        src = "Browse" })
      assert.equal(-72000, Ledger.amount(e))
      assert.equal("Browse", e.src)
    end)

    it("does not count the invoice of a Better AH buy again, named by a link (#150)", function()
      local link = "|cff1eff00|Hitem:1::::::::60:::::|h[Ridge Cleaver]|h|r"
      ledger:buy({ t = NOW, char = "A", name = link, n = 1, c = 2210, src = "Snipe" }, true)
      assert.is_nil(ledger:buyerInvoice({ t = NOW + 60, char = "A", name = "Ridge Cleaver", n = 1, c = 2210 }))
      assert.equal(1, #ledger.store.entries)
      assert.equal(0, #ledger.store.own)
    end)

    it("uses up a commodity buy from several sellers' invoices", function()
      ledger:buy({ t = NOW, char = "A", name = "Runecloth", n = 40, c = 1600 }, true)
      assert.is_nil(ledger:buyerInvoice({ t = NOW, char = "A", name = "Runecloth", n = 25, c = 1000 }))
      assert.equal(1, #ledger.store.own)
      assert.is_nil(ledger:buyerInvoice({ t = NOW, char = "A", name = "Runecloth", n = 15, c = 600 }))
      assert.equal(0, #ledger.store.own)
      -- A third invoice is another buy.
      assert.is_not_nil(ledger:buyerInvoice({ t = NOW, char = "A", name = "Runecloth", n = 1, c = 40 }))
      assert.equal(2, #ledger.store.entries)
    end)

    it("matches an invoice to the buy of its exact price first", function()
      ledger:buy({ t = NOW, char = "A", name = "X", n = 1, c = 10000 }, true)
      ledger:buy({ t = NOW, char = "A", name = "X", n = 1, c = 5000 }, true)
      assert.is_nil(ledger:buyerInvoice({ t = NOW, char = "A", name = "X", n = 1, c = 5000 }))
      assert.is_nil(ledger:buyerInvoice({ t = NOW, char = "A", name = "X", n = 1, c = 10000 }))
      assert.equal(2, #ledger.store.entries)
    end)

    it("matches a buy whose name wasn't known only on its exact price and count", function()
      ledger:buy({ t = NOW, char = "A", n = 2, c = 700 }, true)
      assert.is_not_nil(ledger:buyerInvoice({ t = NOW, char = "A", name = "Y", n = 1, c = 350 }))
      assert.is_nil(ledger:buyerInvoice({ t = NOW, char = "A", name = "Y", n = 2, c = 700 }))
      assert.equal(0, #ledger.store.own)
    end)

    it("records an invoice it can't match as a buy from the mail", function()
      ledger:buy({ t = NOW, char = "A", name = "Runecloth", n = 1, c = 40 }, true)
      local other = ledger:buyerInvoice({ t = NOW, char = "B", name = "Runecloth", n = 1, c = 40 })
      assert.equal("mail", other.src)
      local late = ledger:buyerInvoice({ t = NOW + 31 * DAY, char = "A", name = "Runecloth", n = 1, c = 40 })
      assert.equal("mail", late.src)
      local dearer = ledger:buyerInvoice({ t = NOW, char = "A", name = "Runecloth", n = 1, c = 41 })
      assert.equal("mail", dearer.src)
    end)
  end)

  describe("deposit", function()
    it("records the deposit paid", function()
      local e = ledger:deposit({ t = NOW, char = "A", name = "Arcane Dust", item = 16204, n = 20, c = 120 })
      assert.equal(-120, Ledger.amount(e))
    end)
  end)

  describe("mail", function()
    it("adds up the gold waiting in each character's mailbox", function()
      ledger:setMail("A", 20900, 1, NOW)
      ledger:setMail("B", 100, 2, NOW - 60)
      assert.same({ 21000, 3, NOW - 60 }, { ledger:inMail() })
      assert.same({ 20900, 1, NOW }, { ledger:inMail("A") })
      assert.same({ 0, 0 }, { ledger:inMail("C") })
    end)
  end)

  describe("prune", function()
    it("drops old entries, broken ones and stale own buys", function()
      ledger:deposit({ t = NOW - (Ledger.MAX_DAYS + 1) * DAY, name = "X", c = 1 })
      ledger:deposit({ t = NOW, name = "Y", c = 1 })
      ledger.store.entries[#ledger.store.entries + 1] = { k = "weird", t = NOW }
      ledger:buy({ t = NOW - 31 * DAY, name = "Z", c = 5 }, true)
      ledger:prune(NOW)
      assert.equal(2, #ledger.store.entries)
      assert.equal("Y", ledger.store.entries[1].name)
      assert.equal(0, #ledger.store.own)
    end)

    it("keeps at most MAX_ENTRIES", function()
      local max = Ledger.MAX_ENTRIES
      Ledger.MAX_ENTRIES = 3
      for i = 1, 5 do ledger:deposit({ t = NOW + i, name = "n" .. i, c = 1 }) end
      Ledger.MAX_ENTRIES = max
      assert.equal(3, #ledger.store.entries)
      assert.equal("n3", ledger.store.entries[1].name)
    end)
  end)

  describe("periods", function()
    it("starts days at local midnight", function()
      -- 12:00 UTC is 13:00 at UTC+1: the day began at 23:00 UTC the day before.
      assert.equal(NOW - 13 * 3600, Ledger.dayStart(NOW, 3600))
      assert.equal(NOW - 12 * 3600, Ledger.dayStart(NOW, 0))
    end)

    it("counts today in 7 and 30 days, and all has no start", function()
      local today = Ledger.dayStart(NOW, 3600)
      assert.equal(today, Ledger.periodStart("today", NOW, 3600))
      assert.equal(today - 6 * DAY, Ledger.periodStart("7d", NOW, 3600))
      assert.equal(today - 29 * DAY, Ledger.periodStart("30d", NOW, 3600))
      assert.is_nil(Ledger.periodStart("all", NOW, 3600))
    end)

    it("lists entries from a time and a character, newest first", function()
      ledger:deposit({ t = NOW - 2 * DAY, char = "A", name = "old", c = 1 })
      ledger:deposit({ t = NOW, char = "B", name = "b", c = 1 })
      ledger:deposit({ t = NOW - 60, char = "A", name = "a", c = 1 })
      local names = {}
      for _, e in ipairs(ledger:entries(NOW - DAY)) do names[#names + 1] = e.name end
      assert.same({ "b", "a" }, names)
      assert.equal(2, #ledger:entries(nil, "A"))
      assert.equal("a", ledger:entries(nil, "A")[1].name)
    end)
  end)

  describe("totals", function()
    it("adds up money in and out, with deposits that came back taken off", function()
      ledger:sale({ t = NOW, name = "Shard", n = 2, money = 20900 + 50, cut = 1100, deposit = 50 })
      ledger:buy({ t = NOW, name = "Dust", n = 12, c = 18000 })
      ledger:deposit({ t = NOW, name = "Shard", c = 50 })
      ledger:deposit({ t = NOW, name = "Cleaver", c = 36 })
      local t = Ledger.totals(ledger:entries())
      assert.equal(22000, t.sales)
      assert.equal(1, t.sold)
      assert.equal(1100, t.cut)
      assert.equal(18000, t.purchases)
      assert.equal(12, t.bought)
      assert.equal(86, t.deposits)
      assert.equal(50, t.returned)
      assert.equal(36, t.kept)
      assert.equal(22000, t.moneyIn)
      assert.equal(18000 + 1100 + 36, t.moneyOut)
      assert.equal(22000 - 19136, t.net)
    end)

    it("is all zero with nothing", function()
      local t = Ledger.totals({})
      assert.equal(0, t.net)
      assert.equal(0, t.moneyOut)
    end)
  end)

  describe("byItem", function()
    it("gives each item what was bought, sold and made, best first", function()
      ledger:buy({ t = NOW, name = "Thorium Bar", n = 40, c = 144000 })
      ledger:deposit({ t = NOW, name = "Thorium Bar", n = 40, c = 480 })
      ledger:sale({ t = NOW + 1, name = "Thorium Bar", n = 40, money = 156560 + 480, cut = 8240, deposit = 480 })
      ledger:buy({ t = NOW, name = "Illusion Dust", n = 12, c = 18000 })
      local rows = Ledger.byItem(ledger:entries())
      assert.equal("Thorium Bar", rows[1].name)
      assert.equal(40, rows[1].bought)
      assert.equal(3600, rows[1].avgPaid)
      assert.equal(40, rows[1].sold)
      assert.equal(4120, rows[1].avgSold)
      assert.equal(8240, rows[1].cost)
      assert.equal(164800 - 144000 - 8240, rows[1].profit)
      assert.equal(NOW + 1, rows[1].last)
      assert.equal("Illusion Dust", rows[2].name)
      assert.equal(-18000, rows[2].profit)
      assert.is_nil(rows[2].avgSold)
    end)
  end)

  describe("byDay", function()
    it("has a row for every day of the period, with gold in and out", function()
      local offset = 3600
      local today = Ledger.dayStart(NOW, offset)
      ledger:sale({ t = today + 60, name = "S", money = 1000, cut = 50, deposit = 10 })
      ledger:buy({ t = today - DAY + 60, name = "B", c = 700 })
      ledger:deposit({ t = today - DAY + 120, name = "S", c = 10 })
      local days = Ledger.byDay(ledger:entries(), Ledger.periodStart("7d", NOW, offset), NOW, offset)
      assert.equal(7, #days)
      assert.equal(today, days[7].day)
      assert.equal(1000, days[7].moneyIn)
      assert.equal(0, days[7].moneyOut)
      assert.equal(710, days[6].moneyOut)
      assert.equal(-710, days[6].net)
      assert.equal(0, days[1].entries)
      -- Net over the days is the totals' net.
      local sum = 0
      for _, d in ipairs(days) do sum = sum + d.net end
      assert.equal(Ledger.totals(ledger:entries()).net, sum)
    end)

    it("starts at the oldest entry with no start", function()
      ledger:buy({ t = NOW - 2 * DAY, name = "B", c = 1 })
      assert.equal(3, #Ledger.byDay(ledger:entries(), nil, NOW, 0))
    end)
  end)
end)

describe("Ledger:soldAndPosted (#194)", function()
  it("counts the units sold and posted of one item since a time, by item ID or by name", function()
    local l = Ledger.new({})
    l:deposit({ t = 100, char = "A", name = "Strange Dust", item = 10940, n = 20, c = 50 })
    l:deposit({ t = 10, char = "A", name = "Strange Dust", item = 10940, n = 5, c = 50 }) -- too old
    l:sale({ t = 200, char = "B", name = "Strange Dust", n = 12, money = 2000, cut = 100, deposit = 0 })
    l:sale({ t = 200, char = "B", name = "Soul Dust", n = 3, money = 900, cut = 45, deposit = 0 })
    assert.same({ 12, 20 }, { l:soldAndPosted(10940, "|cffffffff|Hitem:10940::::::::|h[Strange Dust]|h|r", 50) })
    assert.same({ 0, 0 }, { l:soldAndPosted(4251, "Hillman's Shoulders", 50) })
    assert.same({ 0, 25 }, { l:soldAndPosted(10940, nil, 0) }, "by item ID when there is no name")
  end)

  it("keeps a green's suffixes apart, and counts entries booked out of time order", function()
    local l = Ledger.new({})
    l:sale({ t = 300, char = "A", name = "Bandit Cloak of the Monkey", n = 1, money = 900, cut = 45, deposit = 0 })
    l:deposit({ t = 100, char = "A", name = "Bandit Cloak of the Monkey", item = 9789, n = 1, c = 20 })
    l:deposit({ t = 100, char = "A", name = "Bandit Cloak of the Eagle", item = 9789, n = 1, c = 20 })
    l:sale({ t = 150, char = "A", name = "Bandit Cloak of the Monkey", n = 1, money = 900, cut = 45, deposit = 0 })
    assert.same({ 2, 1 }, { l:soldAndPosted(9789, "Bandit Cloak of the Monkey", 50) })
  end)
end)
