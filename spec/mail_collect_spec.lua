local helper = require("spec.helper")
local ns = helper.load("BetterAH/Core/Money.lua")
helper.load("BetterAH/Core/Mailbox.lua", ns)
helper.load("BetterAH/Core/MailCollect.lua", ns)
local MailCollect, Mailbox = ns.MailCollect, ns.Mailbox

local SUBJECTS = { expired = "Auction expired: %s", sold = "Auction successful: %s" }

local function rows(mails) return Mailbox.rows(mails, SUBJECTS) end

local INBOX = {
  { invoice = "seller", subject = "Auction successful: A", money = 100 },
  { subject = "Auction expired: B", items = 2, slots = { { slot = 1, itemID = 11 }, { slot = 3, itemID = 12 } } },
  { sender = "Mirella", subject = "Hi", hasText = true, items = 1, slots = { { slot = 1, itemID = 13 } } },
  { sender = "Krugg", subject = "Lotus", cod = 500, items = 1, slots = { { slot = 1, itemID = 14 } } },
  { sender = "Gorvash", subject = "Mats", money = 50, items = 1, slots = { { slot = 1, itemID = 15 } } },
  { sender = "Blizzard", subject = "Gift", isGM = true, items = 1, slots = { { slot = 1, itemID = 16 } } },
}

describe("MailCollect.ticked", function()
  it("ticks every auction kind and other player mail, not letters, and never COD", function()
    for _, k in ipairs({ "sold", "bought", "outbid", "cancelled", "expired", "other" }) do
      assert.is_true(MailCollect.ticked({}, k), k)
    end
    assert.is_false(MailCollect.ticked({}, "letter"))
    assert.is_false(MailCollect.ticked({ cod = true }, "cod"))
  end)

  it("follows the player's own ticks", function()
    assert.is_true(MailCollect.ticked({ letter = true }, "letter"))
    assert.is_false(MailCollect.ticked({ sold = false }, "sold"))
  end)
end)

describe("MailCollect.preview", function()
  it("adds up the mails, gold and items Collect takes, leaving out letters, COD and a Game Master's mail", function()
    assert.are.same({ mails = 3, gold = 150, items = 3 }, MailCollect.preview(rows(INBOX), {}))
    assert.are.same({ mails = 4, gold = 150, items = 4 }, MailCollect.preview(rows(INBOX), { letter = true }))
  end)
end)

describe("MailCollect.nextTake", function()
  it("takes each mail's money first, then its items from the last slot down", function()
    local r = rows(INBOX)
    local t = MailCollect.nextTake(r, {})
    assert.are.same({ "money", 1 }, { t.take, t.row.index })
    r[1].mail.money = 0
    t = MailCollect.nextTake(r, {})
    assert.are.same({ "item", 2, 3 }, { t.take, t.row.index, t.slot })
  end)

  it("keeps taking money but no items once the bags are full", function()
    local r = rows(INBOX)
    r[1].mail.money = 0
    local t = MailCollect.nextTake(r, {}, { bagsFull = true })
    assert.are.same({ "money", 5 }, { t.take, t.row.index })
    r[5].mail.money = 0
    assert.is_nil(MailCollect.nextTake(r, {}, { bagsFull = true }))
    assert.are.equal(3, MailCollect.itemsLeft(r, {}))
  end)

  it("skips an item the game refused to hand over", function()
    local r = rows(INBOX)
    r[1].mail.money = 0
    local t = MailCollect.nextTake(r, {}, { failed = { [12] = true } })
    assert.are.same({ 2, 1 }, { t.row.index, t.slot })
  end)

  it("never plans a COD, a letter or a Game Master's mail", function()
    local r = rows({ INBOX[3], INBOX[4], INBOX[6] })
    assert.is_nil(MailCollect.nextTake(r, {}))
  end)
end)

describe("MailCollect.summary", function()
  it("sums a run up in one line", function()
    assert.are.equal("Collected 31g 4s: 12 sold, 2 bought, 4 expired back.",
      MailCollect.summary({ money = 310400, kinds = { sold = 12, expired = 4, bought = 2 } }))
    assert.are.equal("Collected 2 mails: 1 cancelled back, 1 other mail.",
      MailCollect.summary({ money = 0, kinds = { cancelled = 1, other = 1 } }))
    assert.are.equal("Nothing collected.", MailCollect.summary({ money = 0, kinds = {} }))
  end)
end)
