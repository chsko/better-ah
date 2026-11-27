local helper = require("spec.helper")
local ns = helper.load("BetterAH/Core/Money.lua")
helper.load("BetterAH/Core/MailSend.lua", ns)
local MailSend = ns.MailSend

describe("MailSend.recipients", function()
  local chars = {
    { key = "Dustwick-7", name = "Dustwick", faction = "Horde" },
    { key = "Korvak-7", name = "Korvak", faction = "Horde" },
    { key = "Mailbank-7", name = "Mailbank", faction = "Horde" },
    { key = "Lightbringer-7", name = "Lightbringer", faction = "Alliance" },
    { key = "Stranger-5", name = "Stranger", faction = "Horde" },
  }

  it("lists your other characters on this server and faction", function()
    assert.are.same({ "Dustwick", "Mailbank" }, MailSend.recipients(chars, "Korvak", "Horde", "7"))
  end)

  it("lists nobody when it can't tell which server this is", function()
    assert.are.same({}, MailSend.recipients(chars, "Korvak", "Horde", nil))
  end)
end)

describe("MailSend.subjectFor and reSubject", function()
  it("names a mail after its first item, with the stack size", function()
    assert.are.equal("Runecloth (20)", MailSend.subjectFor({ { name = "Runecloth", count = 20 } }))
    assert.are.equal("Black Lotus", MailSend.subjectFor({ { name = "Black Lotus", count = 1 } }))
    assert.is_nil(MailSend.subjectFor({}))
  end)

  it("starts a reply's subject with Re: once", function()
    assert.are.equal("Re: About the raid", MailSend.reSubject("About the raid"))
    assert.are.equal("Re: Hi", MailSend.reSubject("Re: Hi"))
  end)
end)

describe("MailSend.amount", function()
  it("reads gold as typed, a bare number as gold", function()
    assert.are.equal(52000, MailSend.amount("5g 20s"))
    assert.are.equal(50000, MailSend.amount("5"))
    assert.are.equal(0, MailSend.amount(""))
    assert.is_nil(MailSend.amount("lots"))
  end)
end)

describe("MailSend.check", function()
  local ITEMS = { { name = "Runecloth", count = 20 } }

  it("needs a recipient", function()
    local mail, why = MailSend.check({ to = " ", subject = "x" }, {})
    assert.is_nil(mail)
    assert.are.equal(MailSend.NO_RECIPIENT, why)
  end)

  it("names a mail without a subject after its item, and needs a subject otherwise", function()
    assert.are.equal("Runecloth (20)", MailSend.check({ to = "Dustwick" }, ITEMS).subject)
    assert.are.equal(MailSend.NO_SUBJECT, select(2, MailSend.check({ to = "Dustwick" }, {})))
  end)

  it("sends gold or a COD, never both", function()
    local gold = MailSend.check({ to = "D", subject = "s", mode = "money", amount = "5g" }, ITEMS)
    assert.are.same({ 50000, 0 }, { gold.money, gold.cod })
    local cod = MailSend.check({ to = "D", subject = "s", mode = "cod", amount = "5g" }, ITEMS)
    assert.are.same({ 0, 50000 }, { cod.money, cod.cod })
  end)

  it("won't send a COD without an item, above the limit, or where COD is off", function()
    assert.are.equal(MailSend.COD_NEEDS_ITEM, select(2, MailSend.check({ to = "D", subject = "s", mode = "cod",
      amount = "5g" }, {})))
    assert.are.equal(MailSend.COD_TOO_MUCH, select(2, MailSend.check({ to = "D", subject = "s", mode = "cod",
      amount = "10001g" }, ITEMS)))
    assert.are.equal(MailSend.COD_OFF, select(2, MailSend.check({ to = "D", subject = "s", mode = "cod",
      amount = "5g" }, ITEMS, { codEnabled = false })))
  end)

  it("won't send more gold than you have with the postage", function()
    assert.are.equal(MailSend.NOT_ENOUGH, select(2, MailSend.check({ to = "D", subject = "s", amount = "5g" }, {},
      { money = 50000, postage = 30 })))
    assert.is_table(MailSend.check({ to = "D", subject = "s", amount = "5g" }, {}, { money = 50030, postage = 30 }))
  end)

  it("says what's wrong with an amount it can't read", function()
    assert.are.equal(MailSend.BAD_AMOUNT, select(2, MailSend.check({ to = "D", subject = "s", amount = "abc" }, {})))
  end)
end)
