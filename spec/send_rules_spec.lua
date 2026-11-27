local helper = require("spec.helper")
local ns = helper.load("BetterAH/Core/Money.lua")
helper.load("BetterAH/Core/Disenchant.lua", ns)
helper.load("BetterAH/Core/Targets.lua", ns)
helper.load("BetterAH/Core/MailSend.lua", ns)
helper.load("BetterAH/Core/SendRules.lua", ns)
local SendRules = ns.SendRules

local RUNECLOTH, MAGEWEAVE, THORIUM = 14047, 4338, 12359
local DUST, ESSENCE = 11176, 11175 -- Dream Dust, Greater Nether Essence

local function stack(bag, slot, itemID, count, extra)
  local s = { bag = bag, slot = slot, itemID = itemID, count = count, name = "item " .. itemID }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end
local function cloth(bag, slot, itemID, count)
  return stack(bag, slot, itemID, count, { classID = 7, subclassID = 5 })
end
local function green(bag, slot, itemID, level, classID, subclassID)
  return stack(bag, slot, itemID, 1, { classID = classID or 4, subclassID = subclassID or 2, quality = 2,
    level = level, equip = "INVTYPE_CHEST" })
end

describe("SendRules.ruleFor", function()
  local rules = {
    { match = "type", type = "cloth", to = "Dustwick" },
    { match = "item", itemID = RUNECLOTH, to = "Mailbank" },
    { match = "group", group = "all", to = "Gorvash" },
    { match = "group", group = "dust", to = "Mailbank" },
  }

  it("lets an item rule beat a type rule, whatever the order", function()
    assert.are.equal(rules[2], SendRules.ruleFor(rules, cloth(0, 1, RUNECLOTH, 20)))
    assert.are.equal(rules[1], SendRules.ruleFor(rules, cloth(0, 1, MAGEWEAVE, 20)))
  end)

  it("lets a disenchant group of one kind beat all enchanting mats", function()
    assert.are.equal(rules[4], SendRules.ruleFor(rules, stack(0, 1, DUST, 5)))
    assert.are.equal(rules[3], SendRules.ruleFor(rules, stack(0, 1, ESSENCE, 5)))
  end)

  it("matches uncommon gear by its disenchant class and item level band", function()
    local r = { { match = "type", type = "armor:26", to = "D" }, { match = "type", type = "weapon:26", to = "W" } }
    assert.are.equal(r[1], SendRules.ruleFor(r, green(0, 1, 1, 28)))
    assert.are.equal(r[2], SendRules.ruleFor(r, green(0, 1, 2, 30, 2, 7)))
    assert.is_nil(SendRules.ruleFor(r, green(0, 1, 3, 31)))
    local blue = green(0, 1, 4, 28)
    blue.quality = 3
    assert.is_nil(SendRules.ruleFor(r, blue))
    assert.is_nil(SendRules.ruleFor(r, stack(0, 1, 5, 1, { classID = 4, subclassID = 2, quality = 2 })))
  end)
end)

describe("SendRules.plan", function()
  it("keeps N of each item in the bags, sending whole stacks", function()
    local rules = { { match = "type", type = "cloth", to = "Dustwick", keep = 20 } }
    local bags = { cloth(0, 1, RUNECLOTH, 20), cloth(0, 2, RUNECLOTH, 20), cloth(0, 3, RUNECLOTH, 5),
      cloth(1, 1, MAGEWEAVE, 15) }
    local p = SendRules.plan(rules, bags)
    assert.are.equal(25, p.items)
    assert.are.equal(25, p.byRule[1].sends)
    assert.are.equal(1, #p.mails)
    assert.are.equal(2, #p.mails[1].items)
  end)

  it("says a rule keeps all when the bags hold no more than the keep", function()
    local rules = { { match = "item", itemID = THORIUM, to = "Gorvash", keep = 10 } }
    local p = SendRules.plan(rules, { stack(0, 1, THORIUM, 10) })
    assert.are.equal(0, p.byRule[1].sends)
    assert.are.equal(10, p.byRule[1].have)
    assert.are.equal("keeps all", SendRules.sendsText(p.byRule[1]))
    assert.are.equal(0, #p.mails)
  end)

  it("puts at most 12 items in a mail, and one recipient per mail", function()
    local rules = { { match = "type", type = "cloth", to = "Dustwick" },
      { match = "item", itemID = THORIUM, to = "Gorvash" } }
    local bags = {}
    for i = 1, 14 do bags[#bags + 1] = cloth(0, i, RUNECLOTH, 20) end
    bags[#bags + 1] = stack(1, 1, THORIUM, 20)
    local p = SendRules.plan(rules, bags)
    assert.are.equal(3, #p.mails)
    assert.are.same({ "Dustwick", "Dustwick", "Gorvash" }, { p.mails[1].to, p.mails[2].to, p.mails[3].to })
    assert.are.same({ 12, 2, 1 }, { #p.mails[1].items, #p.mails[2].items, #p.mails[3].items })
    assert.are.equal(2, p.recipients)
    for _, m in ipairs(p.mails) do
      for _, it in ipairs(m.items) do assert.are.equal(m.to, it.to) end
    end
  end)

  it("never moves gold", function()
    local p = SendRules.plan({ { match = "type", type = "cloth", to = "D" } }, { cloth(0, 1, RUNECLOTH, 20) })
    assert.are.same({ 0, 0 }, { p.mails[1].money, p.mails[1].cod })
  end)

  it("counts postage per item attached", function()
    local rules = { { match = "type", type = "cloth", to = "Dustwick" } }
    local bags = {}
    for i = 1, 13 do bags[#bags + 1] = cloth(0, i, RUNECLOTH, 20) end
    local p = SendRules.plan(rules, bags)
    assert.are.equal(13 * SendRules.POSTAGE, p.postage)
    assert.are.equal("260 items in 2 mails to 1 character  ·  postage 3s 90c", SendRules.footer(p))
  end)

  it("sends nothing to this character, or without a recipient", function()
    local rules = { { match = "type", type = "cloth", to = "korvak" }, { match = "item", itemID = THORIUM, to = " " } }
    local p = SendRules.plan(rules, { cloth(0, 1, RUNECLOTH, 20), stack(0, 2, THORIUM, 5) }, { me = "Korvak" })
    assert.are.equal(0, #p.mails)
    assert.are.equal("Nothing to send.", SendRules.footer(p))
  end)
end)

describe("SendRules.check", function()
  it("needs something to match, a recipient, and a whole keep", function()
    assert.are.equal(SendRules.NO_ITEM, select(2, SendRules.check({ match = "item", to = "D" })))
    assert.are.equal(SendRules.NO_RECIPIENT, select(2, SendRules.check({ match = "type", type = "cloth", to = "" })))
    assert.are.equal(SendRules.BAD_KEEP, select(2, SendRules.check({ match = "type", type = "cloth", to = "D",
      keep = "lots" })))
    assert.are.equal(SendRules.TO_SELF, select(2, SendRules.check({ match = "type", type = "cloth", to = "Korvak" },
      {}, { me = "Korvak" })))
    local r = SendRules.check({ match = "type", type = "cloth", to = " Dustwick ", keep = "20" })
    assert.are.same({ match = "type", type = "cloth", to = "Dustwick", keep = 20 }, r)
  end)

  it("allows one rule per item, group or type, except the one being edited", function()
    local rules = { { match = "type", type = "cloth", to = "D" } }
    assert.are.equal(SendRules.DUPLICATE,
      select(2, SendRules.check({ match = "type", type = "cloth", to = "E" }, rules)))
    assert.is_table(SendRules.check({ match = "type", type = "cloth", to = "E" }, rules, { editing = 1 }))
  end)
end)

describe("SendRules list", function()
  it("adds, edits and deletes rules in the saved list", function()
    local saved = {}
    local list = SendRules.new(saved)
    assert.is_true(list:add({ match = "type", type = "cloth", to = "D" }))
    assert.is_true(list:add({ match = "item", itemID = THORIUM, name = "Thorium Bar", to = "G", keep = 10 }))
    assert.are.equal(2, #saved)
    assert.is_nil(list:add({ match = "type", type = "cloth", to = "X" }))
    assert.is_true(list:update(1, { match = "type", type = "cloth", to = "Mailbank" }))
    assert.are.equal("Mailbank", saved[1].to)
    list:remove(1)
    assert.are.equal(1, #saved)
    assert.are.equal("Thorium Bar", saved[1].name)
  end)

  it("names what a rule matches", function()
    assert.are.equal("Thorium Bar", SendRules.label({ match = "item", itemID = THORIUM, name = "Thorium Bar" }))
    assert.are.equal("Dusts", SendRules.label({ match = "group", group = "dust" }))
    assert.are.equal("Uncommon armor, 26-30", SendRules.label({ match = "type", type = "armor:26" }))
    assert.are.equal("DE group", SendRules.kindLabel({ match = "group" }))
  end)
end)

describe("SendRules.report", function()
  it("says what went out, and to whom", function()
    assert.are.equal("Sent 46 items in 3 mails: 2 to Mailbank, 1 to Dustwick.", SendRules.report({ mails = 3,
      items = 46, planned = 3, to = { { name = "Mailbank", mails = 2 }, { name = "Dustwick", mails = 1 } } }))
  end)

  it("says where it stopped", function()
    assert.are.equal("Sent 12 items in 1 of 3 mails: 1 to Mailbank. Stopped: Mailbank's mailbox is full.",
      SendRules.report({ mails = 1, items = 12, planned = 3, to = { { name = "Mailbank", mails = 1 } },
        stopped = "Mailbank's mailbox is full." }))
    assert.are.equal("Nothing sent. Stopped: no answer.", SendRules.report({ mails = 0, items = 0, planned = 2,
      to = {}, stopped = "no answer." }))
  end)
end)
