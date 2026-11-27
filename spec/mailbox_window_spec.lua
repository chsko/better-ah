local helper = require("spec.helper")
local fake = require("spec.fake_client")

-- A fake client with a mailbox: Blizzard's MailFrame (shown by the client on MAIL_SHOW), an inbox, CloseMail.
local function setup(opts)
  opts = opts or {}
  local env = fake.new()
  local ns = helper.load("BetterAH/Core/Money.lua")
  helper.load("BetterAH/Core/WindowScale.lua", ns)
  helper.load("BetterAH/Core/Mailbox.lua", ns)
  helper.load("BetterAH/Core/MailCollect.lua", ns)
  helper.load("BetterAH/Core/MailSend.lua", ns)
  helper.load("BetterAH/Core/Disenchant.lua", ns)
  helper.load("BetterAH/Core/Targets.lua", ns)
  helper.load("BetterAH/Core/SendRules.lua", ns)
  helper.load("BetterAH/UI/Loading.lua", ns)
  helper.load("BetterAH/UI/WindowResize.lua", ns)
  helper.load("BetterAH/UI/Window.lua", ns)
  helper.load("BetterAH/Game/MailAPI.lua", ns)
  helper.load("BetterAH/Game/MailCollector.lua", ns)
  helper.load("BetterAH/Game/MailSender.lua", ns)
  helper.load("BetterAH/UI/MailSendPanel.lua", ns)
  helper.load("BetterAH/UI/MailRulesPanel.lua", ns)
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
  -- The game sends at most 50 mails; the rest wait on the server until a refresh (env.waiting).
  env.waiting = {}
  env.GetInboxNumItems = function() return #env.mails, #env.mails + #env.waiting end
  env.canCheckIn = 0
  env.answerRefresh = function()
    while #env.mails < 50 and #env.waiting > 0 do env.mails[#env.mails + 1] = table.remove(env.waiting, 1) end
    env.fire("MAIL_INBOX_UPDATE")
  end
  env.checks = 0
  env.CheckInbox = function()
    env.checks = env.checks + 1
    if env.slowRefresh then return end -- the answer comes later, with env.answerRefresh()
    while #env.mails < 50 and #env.waiting > 0 do env.mails[#env.mails + 1] = table.remove(env.waiting, 1) end
    env.fire("MAIL_INBOX_UPDATE")
  end
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
  env.takeTimes = {}
  -- Like the server: auction house mail goes once it is empty.
  local function afterTake(i)
    env.takeTimes[#env.takeTimes + 1] = env.now
    local m = env.mails[i]
    if (m.sender or ""):find("Auction House", 1, true) and (m.money or 0) == 0 and (m.items or 0) == 0 then
      table.remove(env.mails, i)
    end
    env.fire("MAIL_INBOX_UPDATE")
  end
  env.TakeInboxMoney = function(i)
    call("money", i)
    env.mails[i].money = 0
    afterTake(i)
  end
  env.TakeInboxItem = function(i, slot)
    local m = env.mails[i]
    if env.free == 0 then
      call("full", i, slot)
      env.fire("MAIL_FAILED", 1)
      return
    end
    call("item", i, slot)
    m.cod = 0
    if m.attachments then m.attachments[slot] = nil end
    m.items = math.max(0, (m.items or 0) - 1)
    if m.items == 0 then m.itemName = nil end
    afterTake(i)
  end
  env.pending = false
  env.openingAll = {}
  env.C_Mail = {
    CanCheckInbox = function()
      local left = env.canCheckIn - env.now
      return left <= 0, math.max(0, left)
    end,
    IsCommandPending = function() return env.pending end,
    SetOpeningAll = function(on) env.openingAll[#env.openingAll + 1] = on end,
  }
  -- Sending, as the client does it: the attachments live in the game; the cursor carries a bag item.
  env.bags = opts.bags or {}
  env.sendSlots = {}
  env.cursor = nil
  env.sent = {}
  env.player = { money = opts.money or 1000000 }
  env.C_Container.PickupContainerItem = function(bag, slot)
    env.cursor = env.bags[bag] and env.bags[bag][slot]
  end
  env.CursorHasItem = function() return env.cursor ~= nil end
  -- A bag item: { name, count, id = itemID, bound, class, subclass, quality, level }; locked while on the mail.
  local function attached(it)
    for s = 1, 12 do if env.sendSlots[s] == it then return true end end
    return false
  end
  env.C_Container.GetContainerNumSlots = function(bag) return env.bags[bag] and 16 or 0 end
  env.C_Container.GetContainerItemInfo = function(bag, slot)
    local it = env.bags[bag] and env.bags[bag][slot]
    if not it then return nil end
    return { itemID = it.id or 1, stackCount = it[2], itemName = it[1], isBound = it.bound or false,
      isLocked = attached(it), quality = it.quality or 1 }
  end
  local function find(id)
    for _, bag in pairs(env.bags) do
      for _, it in pairs(bag) do if it.id == id then return it end end
    end
  end
  env.C_Item = {
    GetItemInfoInstant = function(id)
      local it = find(id) or {}
      return id, nil, nil, it.equip, nil, it.class, it.subclass
    end,
    GetItemInfo = function(id)
      local it = find(id)
      if it then return it[1], nil, it.quality or 1, it.level or 1 end
    end,
  }
  env.ClickSendMailItemButton = function(i, clear)
    if clear then
      env.sendSlots[i] = nil
    elseif env.cursor then
      local slot = i
      if not slot then
        for s = 1, 12 do if not env.sendSlots[s] then slot = s break end end
      end
      env.sendSlots[slot] = env.cursor
      env.cursor = nil
    end
    env.fire("MAIL_SEND_INFO_UPDATE")
  end
  env.GetSendMailItem = function(i)
    local it = env.sendSlots[i]
    if it then return it[1], it.id or 1, "icon-" .. it[1], it[2] end
  end
  env.GetSendMailPrice = function()
    local n = 0
    for s = 1, 12 do if env.sendSlots[s] then n = n + 1 end end
    return 30 * math.max(1, n)
  end
  env.GetMoney = function() return env.player.money end
  env.C_Mail.IsCODEnabled = function() return not env.codOff end
  env.SetSendMailMoney = function(c) env.sendMoney = c end
  env.SetSendMailCOD = function(c) env.sendCOD = c end
  env.SendMail = function(to, subject, body, replyTo)
    env.sent[#env.sent + 1] = { to = to, subject = subject, body = body, money = env.sendMoney, cod = env.sendCOD,
      replyTo = replyTo }
    if env.refuseSend then
      env.fire("UI_ERROR_MESSAGE", 1, env.refuseSend)
      env.fire("MAIL_FAILED")
      return
    end
    -- What went is gone from the bags.
    for s = 1, 12 do
      local it = env.sendSlots[s]
      if it then
        for _, bag in pairs(env.bags) do
          for slot, b in pairs(bag) do if b == it then bag[slot] = nil end end
        end
      end
    end
    env.sendSlots = {}
    if not env.quietSend then env.fire("MAIL_SEND_SUCCESS") end
  end
  -- Alt-click on a bag item: Blizzard's bag button hands it to HandleModifiedItemClick.
  env.alt = false
  env.IsAltKeyDown = function() return env.alt end
  env.HandleModifiedItemClick = function() return false end
  env.hooksecurefunc = function(name, fn)
    local orig = env[name]
    env[name] = function(...)
      local r = orig(...)
      fn(...)
      return r
    end
  end
  env.altClick = function(bag, slot)
    env.alt = true
    env.HandleModifiedItemClick("link", {
      IsBagAndSlot = function() return true end,
      GetBagAndSlot = function() return bag, slot end,
    })
    env.alt = false
  end
  env.chat = {}
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, line) env.chat[#env.chat + 1] = line end }
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
    local sold, expired = w.kindRows[1], w.kindRows[5]
    assert.are.same({ "Sold", "1", "35s 15c" }, { sold.label:GetText(), sold.count:GetText(), sold.holds:GetText() })
    assert.are.same({ "Expired", "1", "1 item" },
      { expired.label:GetText(), expired.count:GetText(), expired.holds:GetText() })
    assert.truthy(w.collectExpiring:GetText():find("2 expire in under 3 days", 1, true))
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
    assert.are.equal("Nothing to collect", w.collectButton:GetText())
    assert.is_false(w.collectButton:IsEnabled())
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

  it("has an Inbox and a Send tab with the send rules", function()
    local env, _, w = setup({ mails = MAILS })
    env.openMailbox()
    w.tabs.send:Click()
    assert.is_false(w.list:IsShown())
    assert.is_true(w.rulesPanel.frame:IsShown())
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
    assert.is_true(w.collect:IsShown())
    assert.are.equal("Collect", w.collectTitle:GetText())
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

  it("replies to a player's mail: the Send tab opens with the sender and Re: filled in", function()
    local env, _, w = open()
    assert.is_true(w.replyButton:IsEnabled())
    w.replyButton:Click()
    assert.are.equal("send", w.tab)
    assert.are.equal("Mirella", w.sendPanel.to:GetText())
    assert.are.equal("Re: About the raid", w.sendPanel.subject:GetText())
    w.sendPanel.sendButton:Click()
    assert.are.equal(3, env.sent[1].replyTo)
  end)

  it("can't reply to the auction house", function()
    local _, _, w = open(nil, 1)
    assert.is_false(w.replyButton:IsEnabled())
  end)

  it("opens each visit on the inbox summary, with no mail open", function()
    local env, _, w = open()
    env.CloseMail()
    env.openMailbox()
    assert.is_false(w.letter:IsShown())
  end)
end)

describe("Mailbox window: Collect", function()
  local AH = "Horde Auction House"
  local INBOX = {
    { invoice = "seller", sender = AH, subject = "Auction successful: Arcane Dust", money = 3515,
      invoiceItem = "Arcane Dust", invoiceCount = 20 },
    { sender = AH, subject = "Auction expired: Runecloth", items = 2,
      attachments = { { "Runecloth", 20 }, { "Runecloth", 20 } } },
    { sender = "Mirella", subject = "About the raid", body = "See you.", read = true, items = 1,
      attachments = { { "Righteous Orb", 1 } } },
    { sender = "Krugg", subject = "Black Lotus", cod = 40000, items = 1, attachments = { { "Black Lotus", 1 } } },
    { sender = "Gorvash", subject = "Mats", money = 10000, items = 1, attachments = { { "Linen Cloth", 20 } } },
  }

  local function collect(opts)
    opts = opts or {}
    local env, ns, w = setup({ mails = opts.mails or INBOX, settings = opts.settings })
    env.free = opts.free
    env.openMailbox()
    return env, ns, w
  end

  local function runAll(env, w)
    for _ = 1, 40 do
      if not w.collector:running() then return end
      env.runTimers(1)
    end
  end

  it("ticks the auction kinds and other player mail, leaves letters unticked and COD without a box", function()
    local _, _, w = collect()
    local byId = {}
    for _, r in ipairs(w.kindRows) do byId[r.id] = r end
    assert.is_true(byId.sold.box:GetChecked())
    assert.is_true(byId.other.box:GetChecked())
    assert.is_false(byId.letter.box:GetChecked())
    assert.is_nil(byId.cod.box)
    assert.truthy(byId.cod.holds:GetText():find("never", 1, true))
    assert.are.equal("Collect 3 mails", w.collectButton:GetText())
    assert.are.equal("Collect takes 1g 35s 15c and 3 items", w.collectTakes:GetText())
  end)

  it("greys the rows Collect skips", function()
    local _, _, w = collect()
    assert.are.same({ 1, 1, 1 }, w.listRows[1][1].textColor)
    assert.are.same({ 0.55, 0.55, 0.55 }, w.listRows[3][1].textColor, "letter")
    assert.are.same({ 0.55, 0.55, 0.55 }, w.listRows[4][1].textColor, "COD")
  end)

  it("remembers the ticks per account", function()
    local _, ns, w = collect()
    w.kindRows[1].box:Click()
    assert.is_false(ns.mailSettings.collect.sold)
    assert.are.equal("Collect 2 mails", w.collectButton:GetText())
  end)

  it("takes one thing at a time, money before items, the first inside the click", function()
    local env, _, w = collect()
    w.collectButton:Click()
    assert.are.same({ { "money", 1 } }, env.mailCalls, "the first take runs in the click")
    assert.are.equal("Stop collecting", w.collectButton:GetText())
    runAll(env, w)
    assert.are.same({ { "money", 1 }, { "item", 1, 2 }, { "item", 1, 1 }, { "money", 3 }, { "item", 3, 1 } },
      env.mailCalls)
    for i = 2, #env.takeTimes do
      assert.is_true(env.takeTimes[i] - env.takeTimes[i - 1] >= 0.15)
    end
    assert.are.same({ true, false }, env.openingAll)
  end)

  it("waits while the game still has a mail command pending", function()
    local env, _, w = collect()
    w.collectButton:Click()
    env.pending = true
    env.runTimers(3)
    assert.are.equal(1, #env.mailCalls)
    env.pending = false
    env.runTimers(1)
    assert.are.equal(2, #env.mailCalls)
  end)

  it("never takes a COD or a letter, and sums the run up in the window and the chat", function()
    local env, _, w = collect()
    w.collectButton:Click()
    runAll(env, w)
    assert.are.equal("Mirella", env.mails[1].sender)
    assert.are.equal(1, env.mails[1].items, "the letter keeps its item")
    assert.are.equal("Krugg", env.mails[2].sender)
    assert.are.equal(1, env.mails[2].items, "the COD isn't paid")
    assert.are.equal(40000, env.mails[2].cod)
    local line = "Collected 1g 35s: 1 sold, 1 expired back, 1 other mail."
    assert.truthy(w.lastRunText:GetText():find(line, 1, true))
    assert.truthy(env.chat[1]:find(line, 1, true))
    assert.are.equal("Nothing to collect", w.collectButton:GetText())
  end)

  it("keeps taking gold once the bags are full, and says how many items stay in the mail", function()
    local env, _, w = collect({ free = 0 })
    w.collectButton:Click()
    runAll(env, w)
    assert.are.same({ { "money", 1 }, { "money", 4 } }, env.mailCalls)
    assert.truthy(w.lastRunText:GetText():find("3 items stay in the mail", 1, true))
  end)

  it("skips an item the game refused, and carries on with the rest", function()
    local env, _, w = collect()
    env.TakeInboxItem = function(i, slot)
      env.mailCalls[#env.mailCalls + 1] = { "refused", i, slot }
      env.fire("MAIL_FAILED", 1)
    end
    w.collectButton:Click()
    runAll(env, w)
    assert.is_false(w.collector:running())
    -- The fake gives every attachment item ID 1, so one refusal skips both Runecloth stacks.
    assert.are.same({ { "money", 1 }, { "refused", 1, 2 }, { "money", 4 } }, env.mailCalls)
  end)

  it("stops on Stop, and when the mailbox closes", function()
    local env, _, w = collect()
    w.collectButton:Click()
    w.collectButton:Click()
    assert.is_false(w.collector:running())
    env.runTimers(3)
    assert.are.equal(1, #env.mailCalls)
    w.collectButton:Click()
    env.CloseMail()
    assert.is_false(w.collector:running())
    env.runTimers(3)
    assert.are.equal(2, #env.mailCalls)
  end)

  it("leaves gold the game keeps (at the gold cap, say) and goes on with the rest", function()
    local env, _, w = collect({ mails = { { sender = AH, subject = "Auction successful: A", money = 100,
      invoice = "seller" }, { sender = AH, subject = "Auction expired: B", items = 1,
      attachments = { { "B", 1 } } } } })
    env.TakeInboxMoney = function(i) env.mailCalls[#env.mailCalls + 1] = { "kept", i } end
    w.collectButton:Click()
    runAll(env, w)
    assert.are.same({ { "kept", 1 }, { "item", 2, 1 } }, env.mailCalls, "the kept gold isn't asked for again")
    assert.is_false(w.collector:running())
  end)

  it("gives up when takes change nothing and the game doesn't answer", function()
    local env, _, w = collect({ mails = { { sender = AH, subject = "Auction expired: B", items = 1,
      attachments = { { "B", 1 } } } } })
    env.TakeInboxItem = function(i, slot) env.mailCalls[#env.mailCalls + 1] = { "ignored", i, slot } end
    w.collectButton:Click()
    runAll(env, w)
    assert.is_false(w.collector:running())
    assert.are.equal(5, #env.mailCalls)
    assert.truthy(w.lastRunText:GetText():find("Stopped", 1, true))
  end)

  it("reads refused items as full bags, and still takes the gold after them", function()
    local mails = {}
    for i = 1, 6 do
      mails[i] = { sender = AH, subject = "Auction expired: Item " .. i, items = 1, attachments = { { "I" .. i, 1 } } }
    end
    mails[7] = { invoice = "seller", sender = AH, subject = "Auction successful: X", money = 5000 }
    local env, _, w = collect({ mails = mails })
    local id = 100
    env.TakeInboxItem = function(i, slot)
      env.mailCalls[#env.mailCalls + 1] = { "refused", i, slot }
      id = id + 1
      env.fire("MAIL_FAILED", id) -- a different item each time
    end
    w.collectButton:Click()
    runAll(env, w)
    assert.are.same({ "money", 7 }, env.mailCalls[#env.mailCalls])
    assert.are.equal(4, #env.mailCalls, "three refusals, then gold only")
    assert.truthy(w.lastRunText:GetText():find("Collected 50s 0c: 1 sold.", 1, true))
    assert.truthy(w.lastRunText:GetText():find("6 items stay in the mail until you free up bag space", 1, true))
  end)

  it("waits for the last take's answer after Stop, so the summary counts it", function()
    local env, _, w = collect()
    w.collectButton:Click()
    env.pending = true
    w.collectButton:Click()
    assert.is_nil(w.lastRun)
    env.pending = false
    env.runTimers(1)
    assert.truthy(w.lastRunText:GetText():find("Collected 35s 15c: 1 sold.", 1, true))
  end)

  it("keeps its progress and Stop in view: rows don't open while it runs", function()
    local env, _, w = collect()
    w.collectButton:Click()
    w.listRows[2].button:Click()
    assert.is_false(w.letter:IsShown())
    assert.is_true(w.collect:IsShown())
    assert.are.equal("Stop collecting", w.collectButton:GetText())
    runAll(env, w)
  end)

  it("waits at least Blizzard's 0.15 s between takes", function()
    local _, ns = collect()
    assert.is_true(ns.MailCollector.DELAY >= 0.15)
  end)

  it("greys a skipped row's coloured cells too", function()
    local _, _, w = collect()
    assert.is_nil(w.listRows[4][4]:GetText():find("|c", 1, true), "COD row")
  end)
end)

describe("Mailbox window: Collect past the 50 mails the game shows", function()
  local AH = "Horde Auction House"
  local function sold(i)
    return { invoice = "seller", sender = AH, subject = "Auction successful: Item " .. i, money = 100 }
  end

  local function big(shown, waiting, opts)
    opts = opts or {}
    local mails = {}
    for i = 1, shown do mails[i] = opts.letters and { sender = "P" .. i, subject = "s", hasText = true,
      body = "hi", read = true } or sold(i) end
    local env, ns, w = setup({ mails = mails })
    for i = 1, waiting do env.waiting[i] = sold(shown + i) end
    env.openMailbox()
    return env, ns, w
  end

  local function run(env, w, seconds)
    for _ = 1, seconds do
      if not w.collector:running() then return end
      env.runTimers(1)
    end
  end

  it("says how many more mails wait beyond the ones shown", function()
    local _, _, w = big(50, 18)
    assert.truthy(w.footerText:GetText():find("50 of 68 shown  ·  18 more waiting", 1, true))
  end)

  it("finishes the batch, counts down to the refresh, refreshes and carries on", function()
    local env, _, w = big(3, 2)
    env.canCheckIn = env.now + 40
    w.collectButton:Click()
    run(env, w, 5)
    assert.are.equal(0, #env.mails, "the first batch is taken")
    assert.is_true(w.collector:running())
    assert.truthy(w.collectBags:GetText():find("Next mails in 0:3", 1, true))
    assert.are.equal(0, env.checks)
    run(env, w, 60)
    assert.are.equal(1, env.checks)
    assert.is_false(w.collector:running())
    assert.are.equal(0, #env.mails + #env.waiting)
    assert.truthy(w.lastRunText:GetText():find("5 sold", 1, true))
  end)

  it("stops waiting when the mailbox closes", function()
    local env, _, w = big(2, 2)
    env.canCheckIn = env.now + 40
    w.collectButton:Click()
    run(env, w, 4)
    assert.is_true(w.collector:running())
    env.CloseMail()
    assert.is_false(w.collector:running())
    env.runTimers(60)
    assert.are.equal(0, env.checks)
  end)

  it("says so when the mails shown hold nothing to take, as no refresh brings in the rest", function()
    local mails = {}
    for i = 1, 50 do mails[i] = { sender = "P" .. i, subject = "s", hasText = true, body = "hi", read = true } end
    mails[50] = sold(50)
    local env, _, w = setup({ mails = mails })
    for i = 1, 5 do env.waiting[i] = { sender = "Q" .. i, subject = "s", hasText = true, body = "hi", read = true } end
    env.openMailbox()
    -- The sale is taken and the refresh brings in a letter: now 50 letters fill what the game shows.
    w.collectButton:Click()
    run(env, w, 120)
    assert.is_false(w.collector:running())
    assert.are.equal(1, env.checks)
    assert.truthy(w.lastRunText:GetText():find("4 more can't come in", 1, true))
  end)

  it("keeps waiting for the refresh's answer through an inbox update that changes nothing", function()
    local env, _, w = big(2, 2)
    env.slowRefresh = true
    w.collectButton:Click()
    run(env, w, 4)
    assert.are.equal(1, env.checks)
    env.fire("MAIL_INBOX_UPDATE") -- a late update, not the refresh's answer
    run(env, w, 2)
    assert.is_true(w.collector:running())
    assert.truthy(w.collectBags:GetText():find("Fetching the next mails", 1, true))
    env.answerRefresh()
    run(env, w, 10)
    assert.is_false(w.collector:running())
    assert.are.equal(0, #env.mails)
    assert.truthy(w.lastRunText:GetText():find("4 sold", 1, true))
  end)

  it("says so when the game never sends the next mails", function()
    local env, _, w = big(2, 2)
    env.slowRefresh = true
    w.collectButton:Click()
    run(env, w, 40)
    assert.is_false(w.collector:running())
    assert.truthy(w.lastRunText:GetText():find("didn't send the next mails", 1, true))
  end)

  it("still refreshes for waiting gold once the bags are full", function()
    local env, _, w = big(2, 2)
    env.free = 0
    w.collectButton:Click()
    run(env, w, 10)
    assert.are.equal(1, env.checks)
    assert.are.equal(0, #env.mails + #env.waiting)
  end)

  it("asks for the refresh anyway when the countdown never ends", function()
    local env, _, w = big(1, 1)
    env.C_Mail.CanCheckInbox = function() return false, 0 end
    w.collectButton:Click()
    run(env, w, 120)
    assert.are.equal(1, env.checks)
  end)

  it("can fetch the next mails after a stop, when the ones shown hold nothing to take", function()
    local env, _, w = big(1, 2)
    env.canCheckIn = env.now + 40
    w.collectButton:Click()
    run(env, w, 3)
    w.collectButton:Click() -- Stop during the countdown
    assert.are.equal("Fetch the next mails", w.collectButton:GetText())
    env.canCheckIn = 0
    w.collectButton:Click()
    run(env, w, 10)
    assert.are.equal(0, #env.mails + #env.waiting)
  end)
end)

describe("Mailbox window: a new mail", function()
  local BAGS = { [0] = { { "Runecloth", 20, id = 14047 }, { "Arcane Dust", 5, id = 16204 } } }

  local function send(opts)
    opts = opts or {}
    opts.mails = opts.mails or {}
    opts.bags = opts.bags or BAGS
    local env, ns, w = setup(opts)
    env.UnitFactionGroup = function() return "Horde" end
    env.UnitGUID = function() return "Player-7-0A1B2C3D" end
    ns.characters = {
      characters = function()
        return { { key = "Dustwick-7", name = "Dustwick", faction = "Horde" },
          { key = "Korvak-7", name = "Korvak", faction = "Horde" },
          { key = "Mailbank-7", name = "Mailbank", faction = "Horde" },
          { key = "Jaina-7", name = "Jaina", faction = "Alliance" },
          { key = "Twin-5", name = "Twin", faction = "Horde" } }
      end,
    }
    env.openMailbox()
    w.tabs.send:Click()
    return env, ns, w, w.sendPanel
  end

  it("shows the new mail in the Send tab's side panel", function()
    local _, _, w, p = send()
    assert.is_true(p.frame:IsShown())
    assert.is_false(w.collect:IsShown())
    assert.are.equal("Items (0 of 12)  ·  alt-click bag items", p.itemsLabel:GetText())
    assert.are.equal("Postage 30c", p.postage:GetText())
  end)

  it("picks the recipient from your characters on this server and faction", function()
    local _, _, _, p = send()
    p.pick:Click()
    assert.is_true(p.list:IsShown())
    assert.are.same({ "Dustwick", "Mailbank" }, { p.listButtons[1].name, p.listButtons[2].name })
    assert.is_false(p.listButtons[3]:IsShown())
    p.listButtons[2]:Click()
    assert.are.equal("Mailbank", p.to:GetText())
    assert.is_false(p.list:IsShown())
  end)

  it("adds alt-clicked bag items, and a right-click on a slot takes one back", function()
    local env, _, _, p = send()
    env.altClick(0, 1)
    env.altClick(0, 2)
    assert.are.equal("Items (2 of 12)  ·  alt-click bag items", p.itemsLabel:GetText())
    assert.are.equal("20", p.slots[1].count:GetText())
    p.slots[1]:GetScript("OnClick")(p.slots[1], "RightButton")
    assert.is_nil(env.sendSlots[1])
    assert.are.equal("Items (1 of 12)  ·  alt-click bag items", p.itemsLabel:GetText())
  end)

  it("ignores alt-clicks while the Inbox tab is open", function()
    local env, _, w = send()
    w.tabs.inbox:Click()
    env.altClick(0, 1)
    assert.is_nil(env.sendSlots[1])
  end)

  it("takes an item dropped on a slot from the cursor", function()
    local env, _, _, p = send()
    env.C_Container.PickupContainerItem(0, 2)
    p.slots[4]:Click()
    assert.are.equal("Arcane Dust", env.sendSlots[1][1], "into the first free slot, like Blizzard's drop")
  end)

  it("sends gold with the recipient, subject and message, then clears the mail", function()
    local env, _, _, p = send()
    p.to:SetText("Dustwick")
    p.to:GetScript("OnTextChanged")(p.to)
    p.subject:SetText("Gold")
    p.subject:GetScript("OnTextChanged")(p.subject)
    p.body:SetText("For the mats.")
    p.body:GetScript("OnTextChanged")(p.body)
    p.amount:SetText("5g 20s")
    p.amount:GetScript("OnTextChanged")(p.amount)
    p.sendButton:Click()
    assert.are.same({ to = "Dustwick", subject = "Gold", body = "For the mats.", money = 52000, cod = 0 },
      env.sent[1])
    assert.are.equal("Sent to Dustwick.", p.status:GetText())
    assert.are.equal("", p.to:GetText())
  end)

  it("sends a COD for the items, never gold with it, named after the first item", function()
    local env, _, _, p = send()
    env.altClick(0, 1)
    p.draft.to, p.draft.amount = "Dustwick", "3g"
    p.modes.cod:Click()
    p.sendButton:Click()
    assert.are.same({ "Runecloth (20)", 0, 30000 }, { env.sent[1].subject, env.sent[1].money, env.sent[1].cod })
  end)

  it("says what's missing instead of sending", function()
    local env, _, _, p = send()
    p.sendButton:Click()
    assert.are.equal(0, #env.sent)
    assert.truthy(p.status:GetText():find("Type who gets the mail", 1, true))
  end)

  it("shows the game's reason when a send fails, and lets the player try again", function()
    local env, _, _, p = send()
    env.refuseSend = "Cannot find player"
    p.draft.to, p.draft.subject = "Nobody", "Hi"
    p.sendButton:Click()
    assert.are.equal("|cffff6060Not sent: Cannot find player|r", p.status:GetText())
    assert.is_true(p.sendButton:IsEnabled())
    assert.are.equal("Nobody", p.draft.to, "the mail stays as written")
  end)

  it("keeps Send off while Collect runs, so the two don't share the game's answers", function()
    local env, _, w, p = send({ mails = { { invoice = "seller", sender = "Horde Auction House",
      subject = "Auction successful: A", money = 100 } } })
    env.pending = true
    w.tabs.inbox:Click()
    w.collectButton:Click()
    w.tabs.send:Click()
    assert.is_false(p.sendButton:IsEnabled())
    p.draft.to, p.draft.subject = "Dustwick", "Hi"
    p:send()
    assert.are.equal(0, #env.sent)
    w.collector:stop()
  end)

  it("puts a refused item back rather than leaving it on the cursor", function()
    local env, _, _, p = send()
    env.ClickSendMailItemButton = function() end -- the game refuses it
    env.ClearCursor = function() env.cursor = nil end
    env.altClick(0, 1)
    assert.is_nil(env.cursor)
    assert.are.equal("Items (0 of 12)  ·  alt-click bag items", p.itemsLabel:GetText())
  end)

  it("gives Send back on the next visit when a send never got an answer", function()
    local env, _, _, p = send()
    env.SendMail = function() end -- no answer, say the player closed Blizzard's confirmation
    p.draft.to, p.draft.subject = "Dustwick", "Hi"
    p.sendButton:Click()
    assert.is_false(p.sendButton:IsEnabled())
    env.CloseMail()
    env.openMailbox()
    assert.is_true(p.sendButton:IsEnabled())
  end)

  it("gives Send back after a while without an answer", function()
    local env, _, _, p = send()
    env.SendMail = function() end
    p.draft.to, p.draft.subject = "Dustwick", "Hi"
    p.sendButton:Click()
    env.runTimers(31)
    assert.is_true(p.sendButton:IsEnabled())
    assert.truthy(p.status:GetText():find("No answer", 1, true))
  end)

  it("doesn't send as a reply once the recipient changed", function()
    local env, ns, w = setup({ mails = MAILS })
    env.openMailbox()
    w.listRows[3].button:Click()
    w.replyButton:Click()
    local p = w.sendPanel
    p.to:SetText("Dustwick")
    p.to:GetScript("OnTextChanged")(p.to)
    p.sendButton:Click()
    assert.is_nil(env.sent[1].replyTo)
    assert.is_table(ns)
  end)

  it("keeps a half-written mail when another addon's send succeeds", function()
    local env, _, _, p = send()
    p.to:SetText("Dustwick")
    p.to:GetScript("OnTextChanged")(p.to)
    env.fire("MAIL_SEND_SUCCESS")
    assert.are.equal("Dustwick", p.to:GetText())
  end)
end)


describe("Mailbox window: send rules and Send all", function()
  local function bags()
    local cloth = {}
    for i = 1, 14 do cloth[i] = { "Runecloth", 20, id = 14047, class = 7, subclass = 5 } end
    return {
      [0] = cloth,
      [1] = { { "Dream Dust", 10, id = 11176 }, { "Thorium Bar", 10, id = 12359, class = 7, subclass = 7 },
        { "Hearthstone", 1, id = 6948, bound = true } },
    }
  end
  local function rules()
    return {
      { match = "type", type = "cloth", to = "Dustwick", keep = 20 },
      { match = "group", group = "all", to = "Mailbank" },
      { match = "item", itemID = 12359, name = "Thorium Bar", to = "Gorvash", keep = 10 },
    }
  end

  local function open(opts)
    opts = opts or {}
    local env, ns, w = setup({ mails = {}, bags = opts.bags or bags(), settings = { rules = opts.rules or rules() } })
    env.UnitFactionGroup = function() return "Horde" end
    env.UnitGUID = function() return "Player-7-0A1B2C3D" end
    ns.characters = { characters = function()
      return { { key = "Dustwick-7", name = "Dustwick", faction = "Horde" },
        { key = "Mailbank-7", name = "Mailbank", faction = "Horde" } }
    end }
    env.openMailbox()
    w.tabs.send:Click()
    return env, ns, w, w.rulesPanel
  end

  -- Runs the timers until Send all is done.
  local function finish(env, w)
    for _ = 1, 200 do
      if not w.sender:running() then return end
      env.runTimers(1)
    end
  end

  it("lists each rule with what it sends now, and sums it up in the footer", function()
    local _, _, _, r = open()
    assert.are.same({ "Cloth", "type", "Dustwick", "20", "260" },
      { r.rows[1][1]:GetText(), r.rows[1][2]:GetText(), r.rows[1][3]:GetText(), r.rows[1][4]:GetText(),
        r.rows[1][5]:GetText() })
    assert.are.same({ "Enchanting mats", "DE group", "10" },
      { r.rows[2][1]:GetText(), r.rows[2][2]:GetText(), r.rows[2][5]:GetText() })
    assert.are.equal("keeps all", r.rows[3][5]:GetText())
    assert.are.equal("270 items in 3 mails to 2 characters  ·  postage 4s 20c", r.footer:GetText())
    assert.is_true(r.sendAllButton:IsEnabled())
  end)

  it("sends every mail, one at a time, each after the game's answer, then reports", function()
    local env, _, w, r = open()
    local answers = {}
    env.quietSend = true -- the game answers each mail later
    r.sendAllButton:Click()
    assert.are.equal("Stop", r.sendAllButton:GetText())
    env.runTimers(1)
    assert.are.equal(1, #env.sent)
    env.runTimers(5)
    assert.are.equal(1, #env.sent, "no second mail before the first one's answer")
    for _ = 1, 3 do
      answers[#answers + 1] = #env.sent
      env.fire("MAIL_SEND_SUCCESS")
      env.runTimers(2)
    end
    assert.are.same({ 1, 2, 3 }, answers)
    assert.are.equal(3, #env.sent)
    assert.are.same({ "Dustwick", "Dustwick", "Mailbank" }, { env.sent[1].to, env.sent[2].to, env.sent[3].to })
    assert.are.same({ 0, 0 }, { env.sent[1].money, env.sent[1].cod }, "rules never move gold")
    assert.are.equal("Runecloth (20)", env.sent[1].subject)
    assert.is_false(w.sender:running())
    assert.are.equal("Last Send all: Sent 270 items in 3 mails: 2 to Dustwick, 1 to Mailbank.", r.lastText:GetText())
    assert.truthy(env.chat[#env.chat]:find("Sent 270 items", 1, true))
    local left = 0
    for _ in pairs(env.bags[0]) do left = left + 1 end
    assert.are.equal(1, left, "keeps 20 Runecloth")
  end)

  it("stops on MAIL_FAILED, puts the items back and says why", function()
    local env, _, w, r = open()
    env.refuseSend = "Cannot find player"
    r.sendAllButton:Click()
    finish(env, w)
    assert.are.equal(1, #env.sent)
    assert.are.same({}, env.sendSlots)
    assert.are.equal("Last Send all: Nothing sent. Stopped: Cannot find player.", r.lastText:GetText())
  end)

  it("stops once the game answers the mail on its way when Stop is pressed", function()
    local env, _, w, r = open()
    env.quietSend = true
    r.sendAllButton:Click()
    env.runTimers(1)
    r.sendAllButton:Click()
    assert.is_true(w.sender:running())
    env.fire("MAIL_SEND_SUCCESS")
    assert.is_false(w.sender:running())
    assert.are.equal(1, #env.sent)
    assert.truthy(r.lastText:GetText():find("Sent 240 items in 1 of 3 mails: 1 to Dustwick. Stopped", 1, true))
  end)

  it("won't start while the new mail holds items, or while Collect runs", function()
    local env, ns, w, r = open()
    env.altClick(1, 1) -- onto the new mail: no rule is being written
    assert.is_table(env.sendSlots[1])
    r.sendAllButton:Click()
    assert.is_false(w.sender:running())
    assert.are.equal(ns.MailRulesPanel.MAIL_BUSY, r.lastText:GetText())
  end)

  it("won't start while Collect runs", function()
    local env, ns, w, r = open()
    env.mails[1] = { invoice = "seller", sender = "Horde Auction House", subject = "Auction successful: A",
      money = 100 }
    env.fire("MAIL_INBOX_UPDATE")
    env.pending = true
    w.tabs.inbox:Click()
    w.collectButton:Click()
    w.tabs.send:Click()
    r:clickSendAll()
    assert.is_false(w.sender:running())
    assert.are.equal(ns.MailRulesPanel.COLLECTING, r.lastText:GetText())
    w.collector:stop()
  end)

  it("lets go of Blizzard's hidden To box after each mail, and keeps the slots for the run", function()
    local env, _, w, r = open()
    local focused = true
    env.SendMailNameEditBox = { HasFocus = function() return focused end, ClearFocus = function() focused = false end }
    env.quietSend = true
    r.sendAllButton:Click()
    local slot = w.sendPanel.slots[1]
    slot:GetScript("OnClick")(slot, "RightButton")
    assert.is_table(env.sendSlots[1], "a right-click doesn't pull an item off Send all's mail")
    env.runTimers(1)
    focused = true
    env.fire("MAIL_SEND_SUCCESS")
    assert.is_false(focused)
    w.sender:stop()
  end)

  it("says a rule is to you on its own recipient", function()
    local _, _, _, r = open({ rules = { { match = "type", type = "cloth", to = "Korvak" } } })
    assert.are.equal("to you", r.rows[1][5]:GetText())
    assert.are.equal("Nothing to send.", r.footer:GetText())
  end)

  it("reads only the carried bags, not a bank bag", function()
    local _, _, _, r = open({ bags = { [5] = { { "Runecloth", 20, id = 14047, class = 7, subclass = 5 } } } })
    assert.are.equal("Nothing to send.", r.footer:GetText())
  end)

  it("keeps Collect and the new mail's Send off while Send all runs", function()
    local env, _, w, r = open()
    env.quietSend = true
    r.sendAllButton:Click()
    assert.is_false(w.sendPanel.sendButton:IsEnabled())
    w.tabs.inbox:Click()
    assert.is_false(w.collectButton:IsEnabled())
    env.CloseMail()
    assert.is_false(w.sender:running())
  end)

  it("gives up when the game never answers", function()
    local env, _, w, r = open()
    env.quietSend = true
    r.sendAllButton:Click()
    env.runTimers(31)
    assert.is_false(w.sender:running())
    assert.truthy(r.lastText:GetText():find("no answer from the game", 1, true))
  end)

  it("adds a rule for an alt-clicked bag item, edits it and deletes it", function()
    local env, ns, _, r = open({ rules = {} })
    assert.is_true(r.emptyText:IsShown())
    assert.is_false(r.sendAllButton:IsEnabled())
    r.addButton:Click()
    assert.is_true(r.editor:IsShown())
    assert.are.equal("Dustwick", r.toBox:GetText(), "your first character to start with")
    r.saveButton:Click()
    assert.truthy(r.editStatus:GetText():find("Pick what the rule sends", 1, true))
    env.altClick(1, 2)
    assert.is_nil(env.sendSlots[1], "the item names the rule; it isn't attached")
    assert.are.equal("Thorium Bar", r.choiceText:GetText())
    r.keepBox:SetText("5")
    r.keepBox:GetScript("OnTextChanged")(r.keepBox)
    r.saveButton:Click()
    assert.is_false(r.editor:IsShown())
    assert.are.same({ { match = "item", itemID = 12359, name = "Thorium Bar", to = "Dustwick", keep = 5 } },
      ns.mailSettings.rules)
    assert.are.equal("keeps all", r.rows[1][5]:GetText(), "whole stacks: the stack of 10 would leave less than 5")

    r.rows[1].button:Click()
    assert.are.equal("Change rule", r.editTitle:GetText())
    r.matchButtons.type:Click()
    r.nextButton:Click()
    assert.are.equal("Leather", r.choiceText:GetText())
    r.toNext:Click()
    assert.are.equal("Mailbank", r.toBox:GetText())
    r.saveButton:Click()
    assert.are.same({ match = "type", type = "leather", to = "Mailbank", keep = 5 }, ns.mailSettings.rules[1])

    r.rows[1].button:Click()
    r.deleteButton:Click()
    assert.are.same({}, ns.mailSettings.rules)
  end)

  it("won't save a second rule for the same thing", function()
    local _, ns, _, r = open()
    r.addButton:Click()
    r.matchButtons.type:Click()
    r.saveButton:Click()
    assert.truthy(r.editStatus:GetText():find("There is a rule for that already", 1, true))
    assert.are.equal(3, #ns.mailSettings.rules)
  end)
end)
