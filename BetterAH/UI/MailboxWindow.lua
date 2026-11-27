-- The Mailbox window (#149, #154): Better AH's own window, separate from the auction house window, shown instead
-- of Blizzard's mail frame at a mailbox. Inbox lists every mail with its kind (Core/Mailbox.lua); clicking a row
-- opens it in the side panel (#155). Send has the send rules and Send all (#159) beside a new mail (#158).
-- Layout follows the mockup linked from #149.
-- Game calls go through Game/MailAPI.lua.
local _, ns = ...
ns = ns or {}

local MailboxWindow = {}
MailboxWindow.__index = MailboxWindow

local WIDTH, HEIGHT, DETAIL = 760, 470, 280
local TOP = -60
local LIST_WIDTH = WIDTH - DETAIL - 40
MailboxWindow.WIDTH, MailboxWindow.HEIGHT = WIDTH, HEIGHT
-- Laid out for the rows' width beside the scroll bar.
MailboxWindow.COLUMNS = {
  { "Kind", 4, 58, "LEFT" }, { "Item or sender", 66, 186, "LEFT" }, { "Qty", 254, 30 }, { "Gold", 288, 80 },
  { "Left", 372, 44 },
}
MailboxWindow.EMPTY = "No mail."
MailboxWindow.HINT = "click a row to open it"
MailboxWindow.REPLY_TIP = "Opens a new mail to the sender, with Re: and the subject."
MailboxWindow.COD_POPUP = "BETTERAH_MAIL_COD"
local ICON, ICON_STEP, ICONS_PER_ROW = 28, 32, 8

local function money(copper)
  return ns.Money.format(copper)
end

function MailboxWindow.new(env, addon)
  local self = setmetatable({ env = env, addon = addon or {}, rows = {}, offset = 0, tab = "inbox" }, MailboxWindow)
  self.api = self.addon.mailAPI or ns.MailAPI.install(env, self.addon)
  if ns.MailCollector then
    self.collector = self.addon.mailCollector or ns.MailCollector.install(env, self.addon)
    self.collector.hooks = {
      onStep = function() self:render() end,
      onDone = function(run) self:collected(run) end,
    }
  end
  if ns.MailSender and ns.SendRules then
    self.sender = self.addon.mailSender or ns.MailSender.install(env, self.addon)
    self.sender.hooks = {
      onStep = function() self:render() end,
      onDone = function(run)
        if self.rulesPanel then self.rulesPanel:done(run) end
        self:render()
      end,
    }
  end
  return self
end

local function rowsHost(env)
  return setmetatable({ env = env }, { __index = ns.Window })
end

function MailboxWindow:build()
  if self.frame then return self.frame end
  local env, Window = self.env, ns.Window
  local f = env.CreateFrame("Frame", "BetterAHMailFrame", env.UIParent, "PortraitFrameTemplate")
  self.frame = f
  f:SetSize(WIDTH, HEIGHT)
  f:SetPoint("TOPLEFT", env.UIParent, "TOPLEFT", 16, -116)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  -- Escape or the close button: the player is done with the mailbox.
  f:SetScript("OnHide", function()
    self:hideCOD()
    if self.api.open and not self.closing then self.api:closeMail() end
  end)
  if env.UISpecialFrames then table.insert(env.UISpecialFrames, "BetterAHMailFrame") end
  f:SetTitle("Better AH Mailbox")
  f:SetPortraitToAsset("Interface\\Icons\\INV_Letter_15")

  local main = Window.panel(env, f, Window.ART.main)
  main:SetPoint("TOPLEFT", f, "TOPLEFT", 6, TOP)
  main:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(DETAIL + 10), 6)
  self.mainPanel = main
  local text = env.CreateFrame("Frame", nil, f)
  text:SetAllPoints(f)
  text:SetFrameLevel(f:GetFrameLevel() + 1)
  self.textLayer = text

  self.tabs = {}
  for i, t in ipairs({ { "inbox", "Inbox" }, { "send", "Send" } }) do
    local b = env.CreateFrame("Button", nil, text, "UIPanelButtonTemplate")
    b:SetSize(80, 22)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", 60 + (i - 1) * 84, -30)
    b:SetText(t[2])
    b:SetScript("OnClick", function() self:selectTab(t[1]) end)
    self.tabs[t[1]] = b
  end

  local status = text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -36)
  status:SetJustifyH("RIGHT")
  self.statusText = status

  local list = env.CreateFrame("Frame", nil, text)
  list:SetPoint("TOPLEFT", f, "TOPLEFT", 14, TOP + 22)
  list:SetSize(LIST_WIDTH, HEIGHT + TOP - 30)
  self.list = list
  self.listRows = rowsHost(env):buildRows(list, MailboxWindow.COLUMNS, function(r) self:clickRow(r) end,
    function(offset) self:scrollTo(offset) end, LIST_WIDTH)
  if list.EnableMouseWheel then
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) self:scrollTo(self.offset - delta * 3) end)
  end
  local empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  empty:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -56)
  self.emptyText = empty

  local footer = text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 14)
  footer:SetWidth(LIST_WIDTH - 10)
  footer:SetJustifyH("LEFT")
  self.footerText = footer

  if ns.MailRulesPanel and ns.SendRules then
    self.rulesPanel = ns.MailRulesPanel.new(self)
    self.rulesPanel:build(text, LIST_WIDTH, HEIGHT + TOP + 16)
    self.rulesPanel.frame:SetPoint("TOPLEFT", f, "TOPLEFT", 14, TOP + 22)
  end

  local detail = Window.panel(env, f, Window.ART.detail)
  detail:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, TOP)
  detail:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
  detail:SetWidth(DETAIL)
  local dtext = env.CreateFrame("Frame", nil, detail)
  dtext:SetAllPoints(detail)
  dtext:SetFrameLevel(detail:GetFrameLevel() + 1)
  local title = dtext:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", dtext, "TOPLEFT", 12, -12)
  title:SetWidth(DETAIL - 24)
  title:SetJustifyH("LEFT")
  local body = dtext:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  body:SetWidth(DETAIL - 24)
  body:SetJustifyH("LEFT")
  body:SetSpacing(3)
  self.detailPanel, self.detailTitle, self.detailBody = detail, title, body
  self:buildLetter(dtext)
  self:buildCollect(dtext)
  if ns.MailSendPanel and ns.MailSend then
    self.sendPanel = ns.MailSendPanel.new(self)
    self.sendPanel:build(dtext, DETAIL - 24)
    self.api:hookBagClicks(function(bag, slot)
      if self.tab ~= "send" then return end
      -- An item rule being written takes the item; else it goes on the new mail.
      if self.rulesPanel and self.rulesPanel:wantsItem() then
        self.rulesPanel:pickItem(self.api:bagStack(bag, slot))
      else
        self.sendPanel:attachFromBag(bag, slot)
      end
    end)
  end

  if ns.WindowResize and ns.WindowScale then
    local db = self.addon.db
    local saved = db and db.mailWindow or {}
    if db then db.mailWindow = saved end
    self.resize = ns.WindowResize.attach(env, f, WIDTH, HEIGHT, saved, Window.tooltip)
  end
  self:render()
  return f
end

-- The side panel's open mail (#155): who and when, the text, attachments, gold, and what can be done with it.
function MailboxWindow:buildLetter(parent)
  local env, inner = self.env, DETAIL - 24
  local letter = env.CreateFrame("Frame", nil, parent)
  letter:SetAllPoints(parent)
  self.letter = letter
  local function text(font, y, height)
    local fs = letter:CreateFontString(nil, "OVERLAY", font)
    fs:SetPoint("TOPLEFT", letter, "TOPLEFT", 12, y)
    fs:SetWidth(inner)
    if height then fs:SetHeight(height) end
    fs:SetJustifyH("LEFT")
    if fs.SetJustifyV then fs:SetJustifyV("TOP") end
    return fs
  end
  self.letterTitle = text("GameFontNormal", -12)
  self.letterMeta = text("GameFontHighlightSmall", -30)
  self.letterBody = text("GameFontHighlightSmall", -50, 130)
  self.letterBody:SetSpacing(3)
  if self.letterBody.SetMaxLines then self.letterBody:SetMaxLines(9) end
  self.attachLabel = text("GameFontNormalSmall", -188)
  self.attachLabel:SetText("Attached")
  self.icons = {}
  for slot = 1, ns.MailAPI.ATTACHMENTS do
    local b = env.CreateFrame("Button", nil, letter)
    b:SetSize(ICON, ICON)
    local col, row = (slot - 1) % ICONS_PER_ROW, math.floor((slot - 1) / ICONS_PER_ROW)
    b:SetPoint("TOPLEFT", letter, "TOPLEFT", 12 + col * ICON_STEP, -204 - row * ICON_STEP)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 2)
    -- The icon's own attachment slot: slots keep their gaps as items are taken, the icons don't.
    b:SetScript("OnClick", function() if b.attachment then self:clickAttachment(b.attachment.slot) end end)
    b:SetScript("OnEnter", function() self:attachmentTooltip(b) end)
    b:SetScript("OnLeave", function() if env.GameTooltip then env.GameTooltip:Hide() end end)
    b:Hide()
    self.icons[slot] = b
  end
  self.goldLine = text("GameFontHighlight", -276)

  local function button(label, w, h, x, y, onClick)
    local b = env.CreateFrame("Button", nil, letter, "UIPanelButtonTemplate")
    b:SetSize(w, h)
    b:SetPoint("BOTTOMLEFT", letter, "BOTTOMLEFT", x, y)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
  end
  self.takeButton = button("Take all", inner, 28, 12, 70, function() self:takeOpen() end)
  local small = math.floor((inner - 10) / 3)
  self.replyButton = button("Reply", small, 22, 12, 42, function() self:replyOpen() end)
  ns.Window.tooltip(env, self.replyButton, "Reply", MailboxWindow.REPLY_TIP)
  self.returnButton = button("Return", small, 22, 12 + small + 5, 42, function() self:returnOpen() end)
  self.deleteButton = button("Delete", small, 22, 12 + 2 * (small + 5), 42, function() self:deleteOpen() end)
  local note = letter:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  note:SetPoint("BOTTOMLEFT", letter, "BOTTOMLEFT", 12, 12)
  note:SetWidth(inner)
  note:SetJustifyH("LEFT")
  self.letterNote = note
  letter:Hide()
end

-- The side panel while no mail is open (#156): a tick box per kind, what Collect would take, and Collect.
MailboxWindow.COLLECT_HINT = "Tick the kinds Collect takes. Remembered between visits."
MailboxWindow.COLLECTING_HINT = "Taking one mail every 0.15 s. You can keep playing."
MailboxWindow.KIND_LABELS = { other = "Other player mail", letter = "Letters with text" }
MailboxWindow.BAGS_FULL = "Bags full. Gold keeps coming; %s stay in the mail until you free up bag space."
MailboxWindow.ITEMS_LEFT = "%s stay in the mail; open it to take them."
MailboxWindow.NEXT_BATCH = "Next mails in %s. The game allows one inbox refresh a minute. " ..
  "Collect carries on by itself while the mailbox stays open."
MailboxWindow.REFRESHING = "Fetching the next mails..."
MailboxWindow.NO_REFRESH = "The game didn't send the next mails. Close and reopen the mailbox to carry on."
MailboxWindow.FETCH = "Fetch the next mails"
MailboxWindow.BLOCKED = "The mails shown hold nothing Collect takes, so the %d more can't come in. " ..
  "Take or delete some of them first."

-- 0:42 for a countdown.
function MailboxWindow.clock(seconds)
  seconds = math.max(0, math.floor(seconds))
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
local KIND_ROW = 20

function MailboxWindow:buildCollect(parent)
  local env, inner = self.env, DETAIL - 24
  local c = env.CreateFrame("Frame", nil, parent)
  c:SetAllPoints(parent)
  self.collect = c
  local function text(font, y, x, w, justify)
    local fs = c:CreateFontString(nil, "OVERLAY", font)
    fs:SetPoint("TOPLEFT", c, "TOPLEFT", x or 12, y)
    fs:SetWidth(w or inner)
    fs:SetJustifyH(justify or "LEFT")
    return fs
  end
  self.collectTitle = text("GameFontNormal", -12)
  self.collectHint = text("GameFontDisableSmall", -30)
  self.kindRows = {}
  for i, k in ipairs(ns.Mailbox.KINDS) do
    local y = -50 - (i - 1) * KIND_ROW
    local row = { id = k.id }
    if k.id ~= "cod" then
      local box = env.CreateFrame("CheckButton", nil, c, "UICheckButtonTemplate")
      box:SetSize(20, 20)
      box:SetPoint("TOPLEFT", c, "TOPLEFT", 8, y + 3)
      box:SetScript("OnClick", function(b) self:setTick(k.id, b:GetChecked()) end)
      row.box = box
    end
    row.label = text("GameFontHighlightSmall", y, 32, 128)
    row.label:SetText(MailboxWindow.KIND_LABELS[k.id] or k.label)
    row.count = text("GameFontHighlightSmall", y, 160, 22, "RIGHT")
    row.holds = text("GameFontHighlightSmall", y, 186, 70, "RIGHT")
    self.kindRows[i] = row
  end
  self.collectExpiring = text("GameFontHighlightSmall", -50 - #ns.Mailbox.KINDS * KIND_ROW - 6)
  self.collectTakes = text("GameFontHighlight", -50 - #ns.Mailbox.KINDS * KIND_ROW - 28)
  self.collectProgress = text("GameFontHighlight", -50)
  self.collectBags = text("GameFontHighlightSmall", -74)
  if self.collectBags.SetSpacing then self.collectBags:SetSpacing(3) end
  local b = env.CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
  b:SetSize(inner, 28)
  b:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 12, 58)
  b:SetScript("OnClick", function() self:clickCollect() end)
  self.collectButton = b
  local last = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  last:SetPoint("BOTTOMLEFT", c, "BOTTOMLEFT", 12, 12)
  last:SetWidth(inner)
  last:SetJustifyH("LEFT")
  if last.SetSpacing then last:SetSpacing(2) end
  self.lastRunText = last
end

-- The player's Collect ticks, saved per account in BetterAHDB.mail.collect.
function MailboxWindow:ticks()
  local settings = self.addon.mailSettings
  if type(settings) ~= "table" then return {} end
  if type(settings.collect) ~= "table" then settings.collect = {} end
  return settings.collect
end

function MailboxWindow:setTick(kind, on)
  self:ticks()[kind] = on and true or false
  self:render()
end

function MailboxWindow:sending()
  return self.sender ~= nil and self.sender:running()
end

function MailboxWindow:clickCollect()
  local c = self.collector
  if not c then return end
  if c:running() then
    c:stop("stopped")
  elseif not self:sending() then -- Send all and Collect would share the game's MAIL_FAILED
    self.selected = nil
    c:start(self:ticks())
  end
  self:render()
end

-- A run ended: its line goes in the panel and the chat.
function MailboxWindow:collected(run)
  local line = run.summary
  if run.reason == "stuck" then line = line .. " Stopped: the game stopped handing mail over." end
  if run.reason == "cancelled" then line = line .. " Stopped: the game cancelled collecting." end
  if run.reason == "blocked" then line = line .. " " .. string.format(MailboxWindow.BLOCKED, run.more or 0) end
  if run.reason == "norefresh" then line = line .. " " .. MailboxWindow.NO_REFRESH end
  if run.itemsLeft and run.itemsLeft > 0 then
    local left = MailboxWindow.items(run.itemsLeft)
    if run.bagsFull then
      line = line .. " " .. string.format(MailboxWindow.BAGS_FULL, left)
    else
      line = line .. " " .. string.format(MailboxWindow.ITEMS_LEFT, left)
    end
  end
  self.lastRun = line
  -- The list as the run left it, in case the game's inbox update is still on its way.
  if self.api.open then self:setMails(self.api:readInbox()) end
  local chat = self.env.DEFAULT_CHAT_FRAME
  if chat and chat.AddMessage then chat:AddMessage("|cfff2c94cBetter AH|r " .. line) end
  self:render()
end

function MailboxWindow.items(n)
  return n == 1 and "1 item" or (n .. " items")
end

-- What a kind's row says it holds: its gold, else its items.
function MailboxWindow.holds(kind, t)
  if kind == "cod" then return "|cff9d9d9dnever|r" end
  if t.gold > 0 then return money(t.gold) end
  if t.items > 0 then return MailboxWindow.items(t.items) end
  return ""
end

function MailboxWindow:renderCollect(totals)
  local Collect, ticks = ns.MailCollect, self:ticks()
  local collecting = self.collector and self.collector:running()
  local run = self.collector and self.collector.run
  self.collectTitle:SetText(collecting and "Collecting" or "Collect")
  self.collectHint:SetText(collecting and MailboxWindow.COLLECTING_HINT or MailboxWindow.COLLECT_HINT)
  for _, row in ipairs(self.kindRows) do
    local t = totals[row.id]
    row.label:SetShown(not collecting)
    row.count:SetShown(not collecting)
    row.holds:SetShown(not collecting)
    row.count:SetText(t.mails > 0 and tostring(t.mails) or "")
    row.holds:SetText(MailboxWindow.holds(row.id, t))
    if row.box then
      row.box:SetShown(not collecting)
      row.box:SetChecked(Collect.ticked(ticks, row.id))
    end
  end
  local preview = Collect.preview(self.rows, ticks)
  self.collectExpiring:SetShown(not collecting)
  self.collectExpiring:SetText(totals.expiring > 0 and string.format(
    "|cffff9a3c%d expire in under %d days.|r Expired auction mail loses its items.", totals.expiring,
    ns.Mailbox.EXPIRING_DAYS) or "")
  self.collectTakes:SetShown(not collecting)
  local takes = {}
  if preview.gold > 0 then takes[#takes + 1] = money(preview.gold) end
  if preview.items > 0 then takes[#takes + 1] = MailboxWindow.items(preview.items) end
  self.collectTakes:SetText(#takes > 0 and ("Collect takes " .. table.concat(takes, " and ")) or "")
  self.collectProgress:SetShown(collecting and true or false)
  self.collectBags:SetShown(collecting and true or false)
  if collecting then
    local done = run.done == 1 and "1 mail done" or (run.done .. " mails done")
    self.collectProgress:SetText(done .. (run.money > 0 and ("  ·  |cff8fd0ff+" .. money(run.money) .. "|r") or ""))
    local left = run.bagsFull and Collect.itemsLeft(self.rows, ticks) or 0
    local notes = {}
    if run.bagsFull then notes[#notes + 1] = string.format(MailboxWindow.BAGS_FULL, MailboxWindow.items(left)) end
    if run.waiting then
      notes[#notes + 1] = string.format(MailboxWindow.NEXT_BATCH, MailboxWindow.clock(run.waiting))
    elseif run.awaitInbox then
      notes[#notes + 1] = MailboxWindow.REFRESHING
    end
    self.collectBags:SetText(table.concat(notes, "\n\n"))
    self.collectButton:SetText("Stop collecting")
    self.collectButton:SetEnabled(true)
  else
    local n = preview.mails
    -- Nothing to take here, but mail waits beyond what is shown and there is room for it.
    local fetch = n == 0 and self.api:moreWaiting() > 0 and (self.api.shown or 0) < ns.MailCollector.SHOWN
    if fetch then
      self.collectButton:SetText(MailboxWindow.FETCH)
    else
      self.collectButton:SetText(n == 0 and "Nothing to collect" or (n == 1 and "Collect 1 mail" or
        ("Collect " .. n .. " mails")))
    end
    self.collectButton:SetEnabled((n > 0 or fetch) and self.collector ~= nil and not self:sending())
  end
  self.lastRunText:SetText(self.lastRun and ("Last run: " .. self.lastRun) or "")
end

function MailboxWindow:selectTab(id)
  self.tab = id
  self:render()
end

-- Opens the clicked mail in the side panel; clicking the open mail again goes back to the inbox summary.
function MailboxWindow:clickRow(r)
  local row = self.rows[self.offset + r]
  -- While Collect runs the panel shows its progress and Stop, and the mail is the run's to take.
  if not row or (self.collector and self.collector:running()) then return end
  if self.selected and self.selected.index == row.index then
    self.selected = nil
  else
    self.selected = row.mail
  end
  self:hideCOD()
  self:readLetter()
  self:render()
end

function MailboxWindow:readLetter()
  self.openLetter = self.selected and self.api:letter(self.selected.index) or nil
end

function MailboxWindow:takeOpen()
  local mail = self.selected
  if not mail then return end
  if (mail.cod or 0) > 0 then return self:askCOD() end
  self.api:takeAll(mail)
end

function MailboxWindow:clickAttachment(slot)
  local mail = self.selected
  if not mail then return end
  if (mail.cod or 0) > 0 then return self:askCOD(slot) end
  self.api:takeItem(mail, slot)
end

-- COD: the game takes the gold with the first item, so the player says yes first, in Blizzard's own popup.
-- slot: the clicked attachment, taken first (like Blizzard's); else the first one.
-- The yes pays the open mail as it is then (the panel follows it as the inbox changes), only if it is still the
-- same mail with the same amount.
function MailboxWindow:askCOD(slot)
  local env, mail = self.env, self.selected
  if not (env.StaticPopupDialogs and env.StaticPopup_Show) then return end
  if not env.StaticPopupDialogs[MailboxWindow.COD_POPUP] then
    env.StaticPopupDialogs[MailboxWindow.COD_POPUP] = {
      text = "Pay %s to %s for this mail's items?", button1 = "Pay", button2 = "Cancel",
      OnAccept = function(_, data)
        local open = self.selected
        if data and open and open.sender == data.mail.sender and open.subject == data.mail.subject
          and open.cod == data.mail.cod then
          self.api:payCOD(open, data.slot)
        end
      end,
      timeout = 0, whileDead = true, hideOnEscape = true, showAlert = true,
    }
  end
  env.StaticPopup_Show(MailboxWindow.COD_POPUP, money(mail.cod), mail.sender or "the sender",
    { mail = mail, slot = slot })
end

function MailboxWindow:hideCOD()
  if self.env.StaticPopup_Hide then self.env.StaticPopup_Hide(MailboxWindow.COD_POPUP) end
end

function MailboxWindow:replyOpen()
  local mail = self.selected
  if not (mail and self.sendPanel and ns.Mailbox.actions(mail).reply) then return end
  self.sendPanel:reply(mail)
  self:selectTab("send")
end

function MailboxWindow:returnOpen()
  if self.selected then self.api:returnMail(self.selected) end
end

function MailboxWindow:deleteOpen()
  local mail = self.selected
  if mail and ns.Mailbox.actions(mail).delete then self.api:deleteMail(mail) end
end

function MailboxWindow:attachmentTooltip(b)
  local tip, a, mail = self.env.GameTooltip, b.attachment, self.selected
  if not (tip and a and mail) then return end
  tip:SetOwner(b, "ANCHOR_RIGHT")
  if not (tip.SetInboxItem and pcall(tip.SetInboxItem, tip, mail.index, a.slot)) then
    tip:SetText(a.name, 1, 1, 1)
  end
  tip:Show()
end

function MailboxWindow:scrollTo(offset)
  local max = math.max(0, #self.rows - #self.listRows)
  self.offset = math.max(0, math.min(max, math.floor(offset or 0)))
  self:renderRows()
end

-- What the Inbox shows: rows and totals from the mails the adapter read.
function MailboxWindow:setMails(mails)
  local Mailbox = ns.Mailbox
  self.rows = Mailbox.rows(mails, Mailbox.subjects(self.env))
  self.totals = Mailbox.totals(self.rows)
  -- The open mail stays open as the inbox changes under it, until it is gone.
  local found = Mailbox.find(self.rows, self.selected, self.mailCount)
  self.mailCount = #self.rows
  if self.selected and not found then self:hideCOD() end
  self.selected = found and found.mail or nil
  self:readLetter()
  self:scrollTo(self.offset)
  self:render()
end

function MailboxWindow:open(mails)
  self:build()
  self.offset = 0
  self.tab = "inbox"
  self.selected, self.mailCount = nil, nil
  if self.sendPanel then self.sendPanel:reset() end
  self:setMails(mails)
  self.frame:Show()
end

function MailboxWindow:close()
  if not self.frame then return end
  if self.sendPanel then self.sendPanel:reset() end
  self.closing = true
  self.frame:Hide()
  self.closing = nil
end

-- One row's cells: kind, item or sender, qty, gold, left. COD shows what it costs to take.
function MailboxWindow.cells(row)
  local gold = ""
  if row.cod > 0 then gold = "pay " .. money(row.cod)
  elseif row.gold > 0 then gold = "|cff8fd0ff+" .. money(row.gold) .. "|r" end
  local left = row.expiring and ("|cffff9a3c" .. row.left .. "|r") or row.left
  local qty = row.qty and tostring(row.qty) or ""
  return { row.label, row.what, qty, gold, left }
end

function MailboxWindow:renderRows()
  if not self.frame then return end
  local inbox = self.tab == "inbox"
  for i, r in ipairs(self.listRows) do
    local row = inbox and self.rows[self.offset + i]
    local cells = row and MailboxWindow.cells(row)
    r.button:SetShown(row and true or false)
    if r.button.selectedTexture then
      r.button.selectedTexture:SetShown(row and self.selected and row.index == self.selected.index or false)
    end
    -- Rows Collect skips are greyed.
    local skipped = row and ns.MailCollect and not ns.MailCollect.collects(row, self:ticks())
    for c = 1, #MailboxWindow.COLUMNS do
      local cell = cells and cells[c] or ""
      if skipped then cell = cell:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
      r[c]:SetText(cell)
      if skipped then r[c]:SetTextColor(0.55, 0.55, 0.55) else r[c]:SetTextColor(1, 1, 1) end
    end
  end
  ns.Window.syncScrollBar(self.listRows.scrollBar, self.offset, inbox and #self.rows or 0)
end

-- more: mails the game hasn't sent yet (it shows 50 at once, #157).
function MailboxWindow.footer(totals, more)
  local n = totals.mails
  local s = n == 1 and "1 mail" or (n .. " mails")
  if more and more > 0 then s = string.format("%d of %d shown  ·  %d more waiting", n, n + more, more) end
  if n > 0 then s = s .. "  ·  " .. MailboxWindow.HINT end
  if totals.expiring > 0 then
    s = s .. string.format("  ·  |cffff9a3c%d expire in under %d days|r", totals.expiring, ns.Mailbox.EXPIRING_DAYS)
  end
  return s
end

function MailboxWindow:render()
  if not self.frame then return end
  local inbox = self.tab == "inbox"
  for id, b in pairs(self.tabs) do
    if id == self.tab then b:LockHighlight() else b:UnlockHighlight() end
  end
  local totals = self.totals or ns.Mailbox.totals({})
  self.list:SetShown(inbox)
  self.footerText:SetShown(inbox)
  if self.rulesPanel then self.rulesPanel.frame:SetShown(not inbox) end
  self.emptyText:SetText(inbox and #self.rows == 0 and MailboxWindow.EMPTY or "")
  self.footerText:SetText(MailboxWindow.footer(totals, self.api.moreWaiting and self.api:moreWaiting()))
  local name = self.env.UnitName and self.env.UnitName("player")
  local free = self.api:freeSlots()
  self.statusText:SetText((name or "") .. (free and string.format("  ·  bags %d free", free) or ""))
  local open = inbox and self.selected
  self.letter:SetShown(open and true or false)
  self.collect:SetShown(inbox and not open)
  local send = self.sendPanel
  if send then send.frame:SetShown(not inbox) end
  self.detailTitle:SetShown(not inbox and not send)
  self.detailBody:SetShown(not inbox and not send)
  if open then
    self:renderLetter()
  elseif inbox then
    self:renderCollect(totals)
  else
    if send then send:render() end
    if self.rulesPanel then self.rulesPanel:render() end
  end
  self:renderRows()
end

-- The side panel's text for an open mail: "From Mirella · 12d left", the gold line, the body.
function MailboxWindow.letterText(mail, letter)
  local Mailbox = ns.Mailbox
  local left = Mailbox.timeLeft(mail.daysLeft)
  if Mailbox.isExpiring(mail) then left = "|cffff9a3c" .. left .. " left|r" else left = left .. " left" end
  local meta = string.format("From %s  ·  %s", mail.sender or "?", left)
  local gold = ""
  if (mail.cod or 0) > 0 then gold = "COD  |cffff9a3c" .. money(mail.cod) .. "|r"
  elseif (mail.money or 0) > 0 then gold = "Gold attached  |cff8fd0ff+" .. money(mail.money) .. "|r" end
  local body = letter and letter.body or ""
  local invoice = letter and Mailbox.invoiceText(letter.invoice)
  if invoice then body = body ~= "" and (invoice .. "\n\n" .. body) or invoice end
  return meta, gold, body
end

function MailboxWindow:renderLetter()
  local mail, letter = self.selected, self.openLetter or { attachments = {} }
  local meta, gold, body = MailboxWindow.letterText(mail, letter)
  self.letterTitle:SetText((mail.subject and mail.subject ~= "") and mail.subject or "(no subject)")
  self.letterMeta:SetText(meta)
  self.letterBody:SetText(body)
  self.goldLine:SetText(gold)
  self.attachLabel:SetShown(#letter.attachments > 0)
  for i, b in ipairs(self.icons) do
    local a = letter.attachments[i]
    b.attachment = a
    b:SetShown(a and true or false)
    if a then
      b.icon:SetTexture(a.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
      b.count:SetText(a.count > 1 and tostring(a.count) or "")
    end
  end
  local acts = ns.Mailbox.actions(mail)
  self.takeButton:SetText(acts.pay and ("Pay " .. money(acts.pay) .. " and take") or "Take all")
  self.takeButton:SetEnabled(acts.take or acts.pay ~= nil)
  self.replyButton:SetEnabled(acts.reply)
  self.returnButton:SetEnabled(acts.ret)
  self.deleteButton:SetEnabled(acts.delete)
  self.letterNote:SetText(acts.note or "")
end

function MailboxWindow:onEvent(event, ...)
  local c = self.collector
  self.api:onEvent(event, {
    onOpen = function(mails) self:open(mails) end,
    onInbox = function(mails)
      if c then c:inboxUpdated() end
      self:setMails(mails)
    end,
    onClose = function()
      if c then c:stop("closed") end
      if self.sender then self.sender:closed() end
      self:close()
    end,
    onFailed = function(itemID)
      if self.sender and self.sender:failed() then return end
      if self.sendPanel and self.sendPanel:onFailed() then return end
      if c then c:failed(itemID) end
    end,
    onSendInfo = function() if self.sendPanel then self.sendPanel:render() end end,
    onSent = function()
      if self.sender and self.sender:sent() then return self:render() end
      if self.sendPanel then self.sendPanel:onSent() end
    end,
    onError = function(message)
      if self.sender then self.sender:onError(message) end
      if self.sendPanel then self.sendPanel:onError(message) end
    end,
    onBags = function() if self.tab == "send" then self:render() end end,
    onCancelled = function() if c then c:stop("cancelled") end end,
  }, ...)
end

function MailboxWindow.install(env, addon)
  local w = MailboxWindow.new(env, addon)
  local events = env.CreateFrame("Frame")
  for _, e in ipairs(ns.MailAPI.EVENTS) do events:RegisterEvent(e) end
  events:SetScript("OnEvent", function(_, event, ...) w:onEvent(event, ...) end)
  addon.mailboxWindow = w
  return w
end

ns.MailboxWindow = MailboxWindow
if ns.MailAPI and ns.Mailbox and CreateFrame then MailboxWindow.install(_G, ns) end
return MailboxWindow
