local helper = require("spec.helper")
local fake = require("spec.fake_client")

-- A fake client with a mailbox: Blizzard's MailFrame (shown by the client on MAIL_SHOW), an inbox, CloseMail.
local function setup(opts)
  opts = opts or {}
  local env = fake.new()
  local ns = helper.load("BetterAH/Core/Money.lua")
  helper.load("BetterAH/Core/WindowScale.lua", ns)
  helper.load("BetterAH/Core/Mailbox.lua", ns)
  helper.load("BetterAH/UI/Loading.lua", ns)
  helper.load("BetterAH/UI/WindowResize.lua", ns)
  helper.load("BetterAH/UI/Window.lua", ns)
  helper.load("BetterAH/Game/MailAPI.lua", ns)
  helper.load("BetterAH/UI/MailboxWindow.lua", ns)
  ns.db = {}
  ns.mailSettings = opts.settings or {}

  env.AUCTION_OUTBID_MAIL_SUBJECT = "Outbid on %s"
  env.AUCTION_REMOVED_MAIL_SUBJECT = "Auction cancelled: %s"
  env.AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
  env.AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
  env.AUCTION_WON_MAIL_SUBJECT = "Auction won: %s"
  env.UnitName = function() return "Korvak" end
  env.C_Container = { CalculateTotalNumberOfFreeBagSlots = function() return env.free or 9 end }

  -- A copy, as takes change the mails.
  env.mails = {}
  for i, m in ipairs(opts.mails or {}) do
    local copy = {}
    for k, v in pairs(m) do copy[k] = v end
    if m.attachments then
      copy.attachments = {}
      for slot, a in pairs(m.attachments) do copy.attachments[slot] = a end
    end
    env.mails[i] = copy
  end
  env.GetInboxNumItems = function() return #env.mails end
  env.GetInboxHeaderInfo = function(i)
    local m = env.mails[i]
    -- Nobody can reply to the auction house's mail.
    local canReply = not (m.sender or ""):find("Auction House", 1, true)
    return nil, nil, m.sender, m.subject, m.money or 0, m.cod or 0, m.daysLeft or 30, m.items or 0, m.read or false,
      m.returned or false, false, canReply, m.isGM or false
  end
  env.GetInboxInvoiceInfo = function(i)
    local m = env.mails[i]
    if m.invoice then return m.invoice, m.invoiceItem, "Buyer", 0, 0, 0, 0, nil, nil, nil, m.invoiceCount end
  end
  env.GetInboxItem = function(i, slot)
    local m = env.mails[i]
    if m.attachments then
      local a = m.attachments[slot]
      if a then return a[1], 1, "icon-" .. a[1], a[2] end
      return nil
    end
    if m.itemName and (slot == (m.slot or 1) or (m.slot == "all" and slot <= m.items)) then
      return m.itemName, 1, nil, m.count or 1
    end
  end
  env.textRead = {}
  env.GetInboxText = function(i)
    env.textRead[i] = true
    env.mails[i].read = true
    return env.mails[i].body
  end

  -- What the player did with mail, in order: { "loot", 3 }, { "item", 4, 1 }, { "return", 3 }, ...
  env.mailCalls = {}
  local function call(...) env.mailCalls[#env.mailCalls + 1] = { ... } end
  env.AutoLootMailItem = function(i)
    call("loot", i)
    local m = env.mails[i]
    m.money, m.items, m.itemName, m.attachments = 0, 0, nil, nil
  end
  env.TakeInboxMoney = function(i) call("money", i); env.mails[i].money = 0 end
  env.TakeInboxItem = function(i, slot)
    call("item", i, slot)
    local m = env.mails[i]
    m.cod = 0
    if m.attachments then m.attachments[slot] = nil end
  end
  env.ReturnInboxItem = function(i) call("return", i) end
  env.DeleteInboxItem = function(i) call("delete", i) end
  env.StaticPopupDialogs = {}
  env.StaticPopup_Show = function(which, a1, a2, data) env.popup = { which = which, a1, a2, data = data } end
  env.StaticPopup_Hide = function(which) if env.popup and env.popup.which == which then env.popup = nil end end
  env.acceptPopup = function()
    local p = env.popup
    env.popup = nil
    env.StaticPopupDialogs[p.which].OnAccept(nil, p.data)
  end

  -- Like the client: MAIL_SHOW shows Blizzard's frame; CloseMail fires MAIL_CLOSED and hides it, and its
  -- OnHide closes the mail again (a no-op).
  env.MailFrame = env.CreateFrame("Frame", "MailFrame", env.UIParent)
  env.MailFrame:Hide()
  env.mailOpen, env.closedMail = false, 0
  env.CloseMail = function()
    env.closedMail = env.closedMail + 1
    if not env.mailOpen then return end
    env.mailOpen = false
    env.fire("MAIL_CLOSED")
    env.MailFrame:Hide()
  end
  env.MailFrame:SetScript("OnHide", function() env.CloseMail() end)
  env.openMailbox = function()
    env.mailOpen = true
    env.MailFrame:Show()
    env.fire("MAIL_SHOW")
    env.fire("MAIL_INBOX_UPDATE")
  end
  local w = ns.MailboxWindow.install(env, ns)
  return env, ns, w
end

local MAILS = {
  { invoice = "seller", sender = "Horde Auction House", subject = "Auction successful: Arcane Dust",
    money = 3515, daysLeft = 29, invoiceItem = "Arcane Dust", invoiceCount = 20 },
  { sender = "Horde Auction House", subject = "Auction expired: Runecloth", items = 1, itemName = "Runecloth",
    count = 20, daysLeft = 1.125 },
  { sender = "Mirella", subject = "About the raid", body = "See you at 20:00.", items = 1, itemName = "Righteous Orb",
    read = true, daysLeft = 12 },
  { sender = "Krugg", subject = "Black Lotus", items = 1, itemName = "Black Lotus", cod = 40000, daysLeft = 2.9 },
}

describe("Mailbox window", function()
  it("shows instead of Blizzard's mail frame when a mailbox opens", function()
    local env, _, w = setup({ mails = MAILS })
    env.openMailbox()
    assert.is_true(w.frame:IsShown())
    -- Blizzard's frame stays open (its OnHide would close the mailbox) but can't be seen or clicked.
    assert.is_true(env.MailFrame:IsShown())
    assert.are.equal(0, env.MailFrame:GetAlpha())
    assert.is_false(env.MailFrame:IsMouseEnabled())
    assert.are.equal(0, env.closedMail)
  end)

  it("conceals Blizzard's frame the moment it shows, before our MAIL_SHOW handler runs", function()
    local env = setup({ mails = MAILS })
    env.openMailbox()
    env.CloseMail()
    -- Second visit: the hook from the first conceals the frame as it shows.
    env.mailOpen = true
    env.MailFrame:Show()
    assert.are.equal(0, env.MailFrame:GetAlpha())
  end)

  it("leaves Blizzard's frame alone when the replacement is turned off", function()
    local env, _, w = setup({ mails = MAILS, settings = { replace = false } })
    env.openMailbox()
    assert.is_true(w.frame == nil or not w.frame:IsShown())
    assert.are.equal(1, env.MailFrame:GetAlpha())
    assert.is_true(env.MailFrame:IsMouseEnabled())
  end)

  it("hides when the mailbox closes, and gives Blizzard's frame back its look", function()
    local env, _, w = setup({ mails = MAILS })
    env.openMailbox()
    env.CloseMail()
    assert.is_false(w.frame:IsShown())
    assert.are.equal(1, env.MailFrame:GetAlpha())
    assert.are.equal(1, env.MailFrame:GetScale())
  end)

  it("closes the mailbox when the player closes the window", function()
    local env, _, w = setup({ mails = MAILS })
    env.openMailbox()
    w.frame:Hide()
    assert.is_false(env.mailOpen)
    assert.is_true(env.closedMail >= 1)
  end)

  it("lists every mail with its kind, what it holds, gold and time left", function()
    local env, _, w = setup({ mails = MAILS })
    env.openMailbox()
    local rows = w.listRows
    assert.are.equal("Sold", rows[1][1]:GetText())
    assert.are.equal("Arcane Dust", rows[1][2]:GetText())
    assert.are.equal("20", rows[1][3]:GetText())
    assert.truthy(rows[1][4]:GetText():find("35s 15c", 1, true))
    assert.are.equal("Expired", rows[2][1]:GetText())
    assert.are.equal("Runecloth", rows[2][2]:GetText())
    assert.are.equal("20", rows[2][3]:GetText())
    assert.truthy(rows[2][5]:GetText():find("1d 3h", 1, true))
    assert.are.equal("Letter", rows[3][1]:GetText())
    assert.are.equal("Mirella: About the raid", rows[3][2]:GetText())
    assert.are.equal("COD", rows[4][1]:GetText())
    assert.are.equal("pay 4g 0s 0c", rows[4][4]:GetText())
    assert.is_false(rows[5].button:IsShown())
  end)

  it("reads letter text only of player mail the player already read, as reading marks it read", function()
    local mails = {}
    for i, m in ipairs(MAILS) do mails[i] = m end
    mails[5] = { sender = "Gorvash", subject = "Mats", items = 2, itemName = "Linen Cloth", body = "hi" }
    local env, _, w = setup({ mails = mails })
    env.openMailbox()
    assert.is_nil(env.textRead[1], "auction mail")
    assert.is_nil(env.textRead[2], "auction mail")
    assert.is_true(env.textRead[3], "read player mail")
    assert.is_nil(env.textRead[4], "COD")
    assert.is_nil(env.textRead[5], "unread player mail")
    assert.are.equal("Other", w.listRows[5][1]:GetText())
  end)

  it("doesn't take a player's mail for auction mail because of its subject", function()
    local env, _, w = setup({ mails = { { sender = "Prankster", subject = "Auction won: Black Lotus", items = 1 } } })
    env.openMailbox()
    assert.are.equal("Other", w.listRows[1][1]:GetText())
  end)

  it("shows how many items all of a mail's attachments hold", function()
    local env, _, w = setup({ mails = { { sender = "Horde Auction House", subject = "Auction expired: Runecloth",
      items = 2, itemName = "Runecloth", count = 20, slot = "all" } } })
    env.openMailbox()
    assert.are.equal("40", w.listRows[1][3]:GetText())
  end)

  it("writes the raw headers to the debug log when the mailbox opens, not on every inbox update", function()
    local env, ns = setup({ mails = MAILS })
    local lines = {}
    ns.debugLog = { add = function(_, what) lines[#lines + 1] = what end }
    env.openMailbox()
    assert.are.equal(4, #lines)
    env.fire("MAIL_INBOX_UPDATE")
    assert.are.equal(4, #lines)
  end)

  it("gives the player Blizzard's frame if ours fails to open", function()
    local env, _, w = setup({ mails = MAILS })
    w.open = function() error("boom") end
    assert.has_error(function() env.openMailbox() end)
    assert.are.equal(1, env.MailFrame:GetAlpha())
    assert.is_true(env.MailFrame:IsMouseEnabled())
  end)

  it("opens where the player left it, at the size they gave it", function()
    local env, ns, w = setup({ mails = MAILS })
    env.openMailbox()
    w.frame:ClearAllPoints()
    w.frame:SetPoint("TOPLEFT", env.UIParent, "BOTTOMLEFT", 300, 500)
    w.frame:SetScale(1.2)
    w.frame.scripts.OnDragStop(w.frame)
    ns.db.mailWindow.scale = 1.2
    assert.is_number(ns.db.mailWindow.left)
    env.CloseMail()
    w.frame:ClearAllPoints()
    w.frame:SetScale(1)
    env.openMailbox()
    -- The client shows the grip with the window, which puts it back (UI/WindowResize.lua).
    w.resize.grip.scripts.OnShow(w.resize.grip)
    assert.is_true(math.abs(w.frame:GetScale() - 1.2) < 0.001)
    assert.is_true(math.abs(w.frame:GetLeft() * 1.2 - 360) < 1)
  end)

  it("counts what the inbox holds per kind, and mail that expires soon", function()
    local env, _, w = setup({ mails = MAILS })
    env.openMailbox()
    local body = w.detailBody:GetText()
    assert.truthy(body:find("Sold: 1  (35s 15c)", 1, true))
    assert.truthy(body:find("Expired: 1  (1 item)", 1, true))
    assert.truthy(body:find("2 expire in under 3 days", 1, true))
    assert.truthy(w.footerText:GetText():find("4 mails", 1, true))
    assert.truthy(w.statusText:GetText():find("Korvak", 1, true))
    assert.truthy(w.statusText:GetText():find("bags 9 free", 1, true))
  end)

  it("updates the list when the inbox changes", function()
    local env, _, w = setup({ mails = MAILS })
    env.openMailbox()
    table.remove(env.mails, 1)
    env.fire("MAIL_INBOX_UPDATE")
    assert.are.equal("Expired", w.listRows[1][1]:GetText())
    assert.truthy(w.footerText:GetText():find("3 mails", 1, true))
  end)

  it("says so when there is no mail", function()
    local env, _, w = setup({ mails = {} })
    env.openMailbox()
    assert.are.equal("No mail.", w.emptyText:GetText())
    assert.are.equal("No mail.", w.detailBody:GetText())
  end)

  it("scrolls a long inbox", function()
    local mails = {}
    for i = 1, 30 do mails[i] = { sender = "P" .. i, subject = "s" .. i } end
    local env, _, w = setup({ mails = mails })
    env.openMailbox()
    w:scrollTo(10)
    assert.are.equal("P11: s11", w.listRows[1][2]:GetText())
    w:scrollTo(100)
    assert.are.equal("P30: s30", w.listRows[14][2]:GetText())
  end)

  it("has an Inbox and a Send tab; Send is empty for now", function()
    local env, _, w = setup({ mails = MAILS })
    env.openMailbox()
    w.tabs.send:Click()
    assert.is_false(w.list:IsShown())
    assert.is_true(w.sendNote:IsShown())
    w.tabs.inbox:Click()
    assert.is_true(w.list:IsShown())
  end)

  it("keeps its own saved position, apart from the auction house window's", function()
    local env, ns, w = setup({ mails = MAILS })
    env.openMailbox()
    assert.is_table(ns.db.mailWindow)
    assert.is_nil(ns.db.window)
    assert.are.equal("BetterAHMailFrame", w.frame:GetName())
  end)

  it("opens on the Inbox tab at the top on each visit", function()
    local mails = {}
    for i = 1, 30 do mails[i] = { sender = "P" .. i, subject = "s" .. i } end
    local env, _, w = setup({ mails = mails })
    env.openMailbox()
    w.tabs.send:Click()
    w:scrollTo(10)
    env.CloseMail()
    env.openMailbox()
    assert.are.equal("inbox", w.tab)
    assert.are.equal("P1: s1", w.listRows[1][2]:GetText())
  end)
end)

describe("Mailbox window: an open mail", function()
  local function open(mails, row)
    local env, ns, w = setup({ mails = mails or MAILS })
    env.openMailbox()
    w.listRows[row or 3].button:Click()
    return env, ns, w
  end

  it("opens the clicked mail in the side panel: subject, sender, time left, text and attachments", function()
    local env, _, w = open()
    assert.is_true(w.letter:IsShown())
    assert.is_false(w.detailBody:IsShown())
    assert.are.equal("About the raid", w.letterTitle:GetText())
    assert.truthy(w.letterMeta:GetText():find("From Mirella", 1, true))
    assert.truthy(w.letterMeta:GetText():find("12d left", 1, true))
    assert.are.equal("See you at 20:00.", w.letterBody:GetText())
    assert.is_true(w.icons[1]:IsShown())
    assert.is_false(w.icons[2]:IsShown())
    assert.is_true(env.textRead[3])
    assert.is_true(w.listRows[3].button.selectedTexture:IsShown())
    assert.is_false(w.listRows[1].button.selectedTexture:IsShown())
  end)

  it("goes back to the inbox summary when the open mail is clicked again", function()
    local _, _, w = open()
    w.listRows[3].button:Click()
    assert.is_false(w.letter:IsShown())
    assert.are.equal("In this inbox", w.detailTitle:GetText())
  end)

  it("takes the money and every attachment with Take all, through the game's own call", function()
    local env, _, w = open({ { sender = "Gorvash", subject = "Mats", money = 15000,
      attachments = { { "Linen Cloth", 20 }, { "Wool Cloth", 5 } }, items = 2 } }, 1)
    assert.truthy(w.goldLine:GetText():find("1g 50s 0c", 1, true))
    assert.are.equal("20", w.icons[1].count:GetText())
    w.takeButton:Click()
    assert.are.same({ { "loot", 1 } }, env.mailCalls)
    assert.are.equal(0, env.mails[1].money)
  end)

  it("takes one item when its icon is clicked", function()
    local env, _, w = open({ { sender = "Gorvash", subject = "Mats",
      attachments = { { "Linen Cloth", 20 }, { "Wool Cloth", 5 } }, items = 2 } }, 1)
    w.icons[2]:Click()
    assert.are.same({ { "item", 1, 2 } }, env.mailCalls)
  end)

  it("returns a player's mail to its sender, and can't return auction house mail", function()
    local env, _, w = open()
    w.returnButton:Click()
    assert.are.same({ { "return", 3 } }, env.mailCalls)
    w.listRows[2].button:Click()
    assert.is_false(w.returnButton:IsEnabled())
  end)

  it("keeps Delete off while the mail holds items or gold, and deletes it once empty", function()
    local env, _, w = open()
    assert.is_false(w.deleteButton:IsEnabled())
    assert.are.equal("Delete is off until the mail is empty.", w.letterNote:GetText())
    w.deleteButton:Click()
    assert.are.same({}, env.mailCalls)
    env.mails[3].items, env.mails[3].itemName = 0, nil
    env.fire("MAIL_INBOX_UPDATE")
    assert.is_true(w.deleteButton:IsEnabled())
    w.deleteButton:Click()
    assert.are.same({ { "delete", 3 } }, env.mailCalls)
  end)

  it("doesn't delete a mail that got something in it after the panel last looked", function()
    local env, _, w = open({ { sender = "Mirella", subject = "Hi", body = "hey", read = true } }, 1)
    env.mails[1].money = 500 -- no inbox update yet
    w.deleteButton:Click()
    assert.are.same({}, env.mailCalls)
  end)

  it("asks before paying a COD, and pays only on yes", function()
    local env, _, w = open(nil, 4)
    assert.are.equal("Pay 4g 0s 0c and take", w.takeButton:GetText())
    assert.truthy(w.letterNote:GetText():find("The gold goes to Krugg", 1, true))
    w.takeButton:Click()
    assert.are.same({}, env.mailCalls, "nothing paid before the yes")
    assert.are.equal("4g 0s 0c", env.popup[1])
    assert.are.equal("Krugg", env.popup[2])
    w.icons[1]:Click()
    assert.are.same({}, env.mailCalls, "an icon asks too")
    env.acceptPopup()
    assert.are.same({ { "item", 4, 1 } }, env.mailCalls)
  end)

  it("pays the mail the player said yes to, even after mail before it went", function()
    local env, _, w = open(nil, 4)
    w.takeButton:Click()
    table.insert(env.mails, 1, { sender = "Newcomer", subject = "Hi" })
    env.fire("MAIL_INBOX_UPDATE")
    env.acceptPopup()
    assert.are.same({ { "item", 5, 1 } }, env.mailCalls)
  end)

  it("pays with the clicked item first, and keeps the mail open to take the rest", function()
    local env, _, w = open({ { sender = "Krugg", subject = "Herbs", cod = 500, items = 2,
      attachments = { { "Peacebloom", 5 }, { "Silverleaf", 5 } } } }, 1)
    w.icons[2]:Click()
    env.acceptPopup()
    assert.are.same({ { "item", 1, 2 } }, env.mailCalls)
    env.fire("MAIL_INBOX_UPDATE")
    assert.is_true(w.letter:IsShown())
    assert.are.equal("Take all", w.takeButton:GetText())
  end)

  it("closes the COD question when the mailbox closes or the mail is gone", function()
    local env, _, w = open(nil, 4)
    w.takeButton:Click()
    env.CloseMail()
    assert.is_nil(env.popup)
    env.openMailbox()
    w.listRows[4].button:Click()
    w.takeButton:Click()
    table.remove(env.mails, 4)
    env.fire("MAIL_INBOX_UPDATE")
    assert.is_nil(env.popup)
  end)

  it("takes the item an icon shows, also once the slots before it are empty", function()
    local env, _, w = open({ { sender = "Gorvash", subject = "Mats", items = 2,
      attachments = { { "Linen Cloth", 20 }, { "Wool Cloth", 5 } } } }, 1)
    w.icons[1]:Click()
    env.fire("MAIL_INBOX_UPDATE")
    w.icons[1]:Click()
    assert.are.same({ { "item", 1, 1 }, { "item", 1, 2 } }, env.mailCalls)
  end)

  it("doesn't move on to a look-alike mail once the open one is gone", function()
    local env, _, w = open({ { sender = "M", subject = "Hi", body = "a", read = true },
      { sender = "M", subject = "Hi", body = "b", read = true } }, 1)
    w.deleteButton:Click()
    table.remove(env.mails, 1)
    env.fire("MAIL_INBOX_UPDATE")
    assert.is_false(w.letter:IsShown())
    assert.is_nil(env.textRead[2])
  end)

  it("keeps the open mail open as new mail comes in, and closes it once the inbox gets shorter", function()
    local env, _, w = open()
    table.insert(env.mails, 1, { sender = "Newcomer", subject = "Hi" })
    env.fire("MAIL_INBOX_UPDATE")
    assert.are.equal("About the raid", w.letterTitle:GetText())
    assert.is_true(w.listRows[4].button.selectedTexture:IsShown())
    table.remove(env.mails, 4)
    env.fire("MAIL_INBOX_UPDATE")
    assert.is_false(w.letter:IsShown())
  end)

  it("shows a sale's buyer and what the gold is made of", function()
    local mails = { { invoice = "seller", sender = "Horde Auction House", subject = "Auction successful: Arcane Dust",
      money = 3515, invoiceItem = "Arcane Dust", invoiceCount = 20 } }
    local _, _, w = open(mails, 1)
    assert.truthy(w.letterBody:GetText():find("Sold to Buyer", 1, true))
  end)

  it("has a Reply button that stays off until the Send tab can write mail", function()
    local _, _, w = open()
    assert.is_true(w.replyButton:IsShown())
    assert.is_false(w.replyButton:IsEnabled())
  end)

  it("opens each visit on the inbox summary, with no mail open", function()
    local env, _, w = open()
    env.CloseMail()
    env.openMailbox()
    assert.is_false(w.letter:IsShown())
  end)
end)

