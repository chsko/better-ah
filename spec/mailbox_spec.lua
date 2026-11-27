local helper = require("spec.helper")
local ns = helper.load("BetterAH/Core/Money.lua")
helper.load("BetterAH/Core/Mailbox.lua", ns)
local Mailbox = ns.Mailbox

-- The auction house's mail subjects, as the client's global strings give them (enUS).
local SUBJECTS = {
  outbid = "Outbid on %s",
  cancelled = "Auction cancelled: %s",
  expired = "Auction expired: %s",
  sold = "Auction successful: %s",
  won = "Auction won: %s",
}

local function kind(mail) return Mailbox.kind(mail, SUBJECTS) end

describe("Mailbox.kind", function()
  it("calls a seller invoice Sold and a buyer invoice Bought", function()
    assert.are.equal("sold", kind({ invoice = "seller", subject = "Auction successful: Arcane Dust", money = 3515 }))
    assert.are.equal("bought", kind({ invoice = "buyer", subject = "Auction won: Arcane Dust", items = 1 }))
  end)

  it("calls a temporary seller invoice Sold too", function()
    assert.are.equal("sold", kind({ invoice = "seller_temp_invoice", subject = "Sale Pending: Arcane Dust" }))
  end)

  it("knows outbid, cancelled and expired mail by its subject", function()
    assert.are.equal("outbid", kind({ subject = "Outbid on Thorium Bar", money = 68000 }))
    assert.are.equal("cancelled", kind({ subject = "Auction cancelled: Battleforge Shoulderpads", items = 1 }))
    assert.are.equal("expired", kind({ subject = "Auction expired: Runecloth", items = 1 }))
  end)

  it("falls back to the sold and won subjects when there is no invoice", function()
    assert.are.equal("sold", kind({ subject = "Auction successful: Arcane Dust", money = 1 }))
    assert.are.equal("bought", kind({ subject = "Auction won: Arcane Dust", items = 1 }))
  end)

  it("calls any mail with a COD amount COD, before anything else", function()
    assert.are.equal("cod", kind({ sender = "Krugg", subject = "Black Lotus", cod = 40000, items = 1, hasText = true }))
  end)

  it("calls player mail with text a Letter, and other player mail Other", function()
    assert.are.equal("letter", kind({ sender = "Mirella", subject = "About the raid", hasText = true, items = 1 }))
    assert.are.equal("other", kind({ sender = "Gorvash", subject = "Mats", items = 3, money = 100000 }))
  end)

  it("matches subjects literally, so item names with pattern characters still work", function()
    assert.are.equal("expired", kind({ subject = "Auction expired: Potion (Major) [50%]", items = 1 }))
  end)

  it("calls a Game Master's mail a Letter, so it is read rather than collected", function()
    assert.are.equal("letter", kind({ sender = "Blizzard", subject = "Ticket", items = 1, isGM = true }))
  end)

  it("treats a missing subject as player mail", function()
    assert.are.equal("other", kind({ sender = "Gorvash", items = 1 }))
  end)

  it("calls unread player mail that holds nothing a Letter, and read mail without text Other", function()
    assert.are.equal("letter", kind({ sender = "Mirella", subject = "Hi", canReply = true }))
    assert.are.equal("other", kind({ sender = "Mirella", subject = "Hi", canReply = true, hasText = false }))
  end)

  it("reads a subject only on mail nobody can reply to", function()
    assert.are.equal("other", kind({ sender = "P", subject = "Auction won: Lotus", items = 1, canReply = true }))
  end)
end)

describe("Mailbox.timeLeft", function()
  it("shows whole days from 3 days up, and days and hours below", function()
    assert.are.equal("29d", Mailbox.timeLeft(29.4))
    assert.are.equal("3d", Mailbox.timeLeft(3))
    assert.are.equal("2d 6h", Mailbox.timeLeft(2.25))
    assert.are.equal("2d 23h", Mailbox.timeLeft(2.999), "never 3d 0h while under 3 days")
    assert.are.equal("20h", Mailbox.timeLeft(20 / 24))
    assert.are.equal("<1h", Mailbox.timeLeft(0.01))
  end)
end)

describe("Mailbox.isExpiring", function()
  it("is true under 3 days left, not at 3", function()
    assert.is_true(Mailbox.isExpiring({ daysLeft = 2.99 }))
    assert.is_false(Mailbox.isExpiring({ daysLeft = 3 }))
    assert.is_false(Mailbox.isExpiring({}))
  end)
end)

describe("Mailbox.rows", function()
  local mails = {
    { index = 1, invoice = "seller", subject = "Auction successful: Arcane Dust", itemName = "Arcane Dust",
      count = 20, money = 3515, daysLeft = 29 },
    { index = 2, subject = "Auction expired: Runecloth", itemName = "Runecloth", count = 20, items = 1,
      daysLeft = 1.125 },
    { index = 3, sender = "Gorvash", subject = "Mats", items = 3, money = 100000, daysLeft = 25 },
    { index = 4, sender = "Krugg", subject = "Black Lotus", itemName = "Black Lotus", count = 1, items = 1,
      cod = 40000, daysLeft = 2.9 },
  }

  it("gives each mail its kind, what it holds, its gold and time left", function()
    local rows = Mailbox.rows(mails, SUBJECTS)
    assert.are.equal(4, #rows)
    assert.are.same({ "sold", "Sold", "Arcane Dust", 20, 3515, "29d", false },
      { rows[1].kind, rows[1].label, rows[1].what, rows[1].qty, rows[1].gold, rows[1].left, rows[1].expiring })
    assert.are.same({ "expired", "Runecloth", true }, { rows[2].kind, rows[2].what, rows[2].expiring })
    assert.are.equal("1d 3h", rows[2].left)
    assert.are.equal("Gorvash: 3 items", rows[3].what)
    assert.are.equal(3, rows[3].qty)
    assert.are.equal("Krugg: Black Lotus", rows[4].what)
    assert.are.equal(40000, rows[4].cod)
    assert.are.equal(3, rows[3].index)
  end)

  it("names a mail with one item from the sender, and an empty one by its subject", function()
    local rows = Mailbox.rows({
      { sender = "Gorvash", items = 1, itemName = "Linen Cloth", count = 5 },
      { sender = "Mirella", subject = "Hi", hasText = true },
    }, SUBJECTS)
    assert.are.equal("Gorvash: Linen Cloth", rows[1].what)
    assert.are.equal(5, rows[1].qty)
    assert.are.equal("Mirella: Hi", rows[2].what)
  end)
end)

describe("Mailbox.totals", function()
  it("counts mails, gold and items per kind, and mail that expires soon", function()
    local rows = Mailbox.rows({
      { invoice = "seller", subject = "Auction successful: A", money = 100, daysLeft = 29 },
      { invoice = "seller", subject = "Auction successful: B", money = 250, daysLeft = 28 },
      { subject = "Auction expired: C", items = 1, count = 20, daysLeft = 1 },
      { subject = "Auction expired: D", items = 2, count = 1, daysLeft = 2 },
      { sender = "Krugg", cod = 5, items = 1, daysLeft = 10 },
    }, SUBJECTS)
    local t = Mailbox.totals(rows)
    assert.are.same({ mails = 2, gold = 350, items = 0 }, t.sold)
    assert.are.same({ mails = 2, gold = 0, items = 3 }, t.expired)
    assert.are.same({ mails = 1, gold = 0, items = 1 }, t.cod)
    assert.are.equal(2, t.expiring)
    assert.are.equal(5, t.mails)
  end)
end)

describe("Mailbox.KINDS", function()
  it("lists the kinds in the order the window shows them", function()
    local ids = {}
    for i, k in ipairs(Mailbox.KINDS) do ids[i] = k.id end
    assert.are.same({ "sold", "bought", "outbid", "cancelled", "expired", "other", "letter", "cod" }, ids)
  end)
end)

describe("Mailbox.actions", function()
  it("takes all from mail that holds something, and keeps Delete off until it is empty", function()
    local a = Mailbox.actions({ sender = "Gorvash", items = 2, money = 100, canReply = true })
    assert.is_true(a.take)
    assert.is_nil(a.pay)
    assert.is_false(a.delete)
    assert.is_true(a.ret)
    assert.are.equal("Delete is off until the mail is empty.", a.note)
  end)

  it("lets an empty mail be deleted, with nothing to take", function()
    local a = Mailbox.actions({ sender = "Mirella", canReply = true, hasText = true })
    assert.is_false(a.take)
    assert.is_true(a.delete)
    assert.is_nil(a.note)
  end)

  it("asks for the COD amount before the items, and names who gets the gold", function()
    local a = Mailbox.actions({ sender = "Krugg", items = 1, cod = 40000, canReply = true })
    assert.are.equal(40000, a.pay)
    assert.is_false(a.take)
    assert.is_false(a.delete)
    assert.are.equal("Pay 4g 0s 0c to take the items. The gold goes to Krugg.", a.note)
  end)

  it("can't return auction house mail, a Game Master's mail or mail that came back", function()
    assert.is_false(Mailbox.actions({ items = 1, canReply = false }).ret)
    assert.is_false(Mailbox.actions({ items = 1, canReply = true, isGM = true }).ret)
    assert.is_false(Mailbox.actions({ items = 1, canReply = true, wasReturned = true }).ret)
  end)

  it("keeps Reply off until the Send tab can write a mail", function()
    assert.is_false(Mailbox.actions({ canReply = true }).reply)
  end)
end)

describe("Mailbox.invoiceText", function()
  it("says who bought, for how much, and what the gold is made of", function()
    assert.are.equal("Sold to Thrall for 50s 0c. Deposit back 1s 0c, auction house cut 2s 50c.",
      Mailbox.invoiceText({ type = "seller", player = "Thrall", bid = 5000, deposit = 100, consignment = 250 }))
    assert.are.equal("Bought from Jaina for 1g 0s 0c.",
      Mailbox.invoiceText({ type = "buyer", player = "Jaina", bid = 10000 }))
    assert.truthy(Mailbox.invoiceText({ type = "seller_temp_invoice", player = "T", bid = 1 })
      :find("later mail", 1, true))
    assert.is_nil(Mailbox.invoiceText(nil))
  end)
end)

describe("Mailbox.find", function()
  it("follows an open mail as mail before it goes, and loses it once it is gone", function()
    local rows = Mailbox.rows({
      { index = 1, sender = "A", subject = "x" }, { index = 2, sender = "B", subject = "y" },
    }, SUBJECTS)
    assert.are.equal(2, Mailbox.find(rows, { index = 3, sender = "B", subject = "y" }).index)
    assert.is_nil(Mailbox.find(rows, { index = 1, sender = "C", subject = "z" }))
    assert.is_nil(Mailbox.find(rows, nil))
  end)
end)

describe("Mailbox.find, when the inbox got shorter", function()
  it("lets the open mail go rather than follow a look-alike", function()
    local rows = Mailbox.rows({ { index = 1, sender = "M", subject = "Hi" } }, SUBJECTS)
    assert.is_nil(Mailbox.find(rows, { index = 1, sender = "M", subject = "Hi" }, 2))
    assert.are.equal(1, Mailbox.find(rows, { index = 1, sender = "M", subject = "Hi" }, 1).index)
  end)

  it("offers Return only for player mail that holds something", function()
    assert.is_false(Mailbox.actions({ canReply = true, hasText = true }).ret)
  end)
end)
