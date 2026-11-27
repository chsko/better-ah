-- The mail adapter (#149, #154): the Mailbox window's only contact with the game's mail API. It reads the inbox
-- into plain tables for Core/Mailbox.lua, keeps Blizzard's mail frame out of sight while ours replaces it, and
-- closes the mailbox. Taking mail (later tickets) goes through the game's own Take calls, which the Ledger
-- (Game/LedgerAPI.lua) already hooks, so this file adds no hooks of its own.
--
-- Needs the client to check: the window shows at a mailbox instead of Blizzard's frame; the kinds match the
-- subjects the debug log records ("mail" lines); GetInboxText on an unopened mail doesn't break anything.
local _, ns = ...
ns = ns or {}

local MailAPI = {}
MailAPI.__index = MailAPI

MailAPI.EVENTS = { "MAIL_SHOW", "MAIL_INBOX_UPDATE", "MAIL_CLOSED", "MAIL_FAILED", "MAIL_OPEN_ALL_CANCELED" }
MailAPI.ATTACHMENTS = 16 -- ATTACHMENTS_MAX_RECEIVE in Forever's MailFrame.lua

local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if r[1] then return unpack(r, 2, table.maxn(r)) end
  return nil
end

-- addon is the namespace; addon.mailSettings (BetterAHDB.mail, loaded later than this file) holds
-- replace = false when the player turned the replacement off.
function MailAPI.new(env, addon)
  return setmetatable({ env = env, addon = addon or {}, concealed = nil, open = false }, MailAPI)
end

function MailAPI:replacing()
  local s = self.addon.mailSettings
  return not (type(s) == "table" and s.replace == false)
end

-- One mail: { index, sender, subject, money, cod, daysLeft, items, itemName, count, hasText, invoice, isGM,
-- canReply, wasReturned, slots = { { slot, itemID } } (the attachments, for Collect) }.
function MailAPI:readMail(i)
  local env = self.env
  local _, _, sender, subject, money, cod, daysLeft, items, wasRead, wasReturned, _, canReply, isGM =
    try(env.GetInboxHeaderInfo, i)
  local mail = { index = i, sender = sender, subject = subject, money = money or 0, cod = cod or 0,
    daysLeft = daysLeft, items = tonumber(items) or 0, isGM = isGM and true or nil,
    canReply = canReply and true or false, wasReturned = wasReturned and true or nil }
  -- An invoice names its item and count, also for a sale's gold mail that holds no item.
  local invoice, invoiceItem, _, _, _, _, _, _, _, _, invoiceCount = try(env.GetInboxInvoiceInfo, i)
  mail.invoice = invoice
  -- The first attachment names the mail; count adds up every attachment.
  if mail.items > 0 then
    local total = 0
    mail.slots = {}
    for slot = 1, MailAPI.ATTACHMENTS do
      local name, itemID, _, count = try(env.GetInboxItem, i, slot)
      if name or itemID then -- an item not cached yet has an ID but no name
        mail.itemName = mail.itemName or name
        total = total + (tonumber(count) or 1)
        mail.slots[#mail.slots + 1] = { slot = slot, itemID = itemID }
      end
    end
    if total > 0 then mail.count = total end
  end
  if invoice then
    mail.itemName = mail.itemName or invoiceItem
    mail.count = mail.count or invoiceCount
  end
  -- Only plain player mail can be a letter. GetInboxText marks a mail read, so it is asked only of mail the
  -- player already read; an unread one is a letter when it holds nothing (Core/Mailbox.lua).
  if wasRead and ns.Mailbox and ns.Mailbox.kind(mail, self.subjects) == "other" then
    local body = try(env.GetInboxText, i)
    mail.hasText = type(body) == "string" and body:match("%S") ~= nil
  end
  return mail
end

-- log: write the raw headers to the debug log (on MAIL_SHOW only, as MAIL_INBOX_UPDATE fires on every take).
function MailAPI:readInbox(log)
  self.subjects = ns.Mailbox and ns.Mailbox.subjects(self.env)
  local n = try(self.env.GetInboxNumItems) or 0
  local mails = {}
  for i = 1, n do mails[i] = self:readMail(i) end
  if log then MailAPI.log(mails) end
  return mails
end

-- The raw headers go to the debug log, to check the kind rules against Forever's real subjects.
function MailAPI.log(mails)
  local log = ns.debugLog
  if not (log and log.add) then return end
  for _, m in ipairs(mails) do
    pcall(log.add, log, "mail", "%d from=%s subject=%s money=%s cod=%s items=%s invoice=%s reply=%s gm=%s days=%s",
      m.index, tostring(m.sender), tostring(m.subject), tostring(m.money), tostring(m.cod), tostring(m.items),
      tostring(m.invoice), tostring(m.canReply), tostring(m.isGM), tostring(m.daysLeft))
  end
end

-- An opened mail, for the side panel (#155): its text, every attachment and the invoice. Opening reads the text,
-- which marks the mail read, as opening it in Blizzard's frame does.
function MailAPI:letter(i)
  local env = self.env
  local body = try(env.GetInboxText, i)
  local letter = { body = type(body) == "string" and body or "", attachments = {} }
  for slot = 1, MailAPI.ATTACHMENTS do
    local name, itemID, texture, count = try(env.GetInboxItem, i, slot)
    if name then
      letter.attachments[#letter.attachments + 1] = { slot = slot, name = name, itemID = itemID,
        texture = texture, count = tonumber(count) or 1 }
    end
  end
  local kind, _, player, bid, _, deposit, consignment = try(env.GetInboxInvoiceInfo, i)
  if kind then
    letter.invoice = { type = kind, player = player, bid = bid, deposit = deposit, consignment = consignment }
  end
  return letter
end

-- Is mail i still the mail the player opened? The inbox can change between a click and a popup's answer.
function MailAPI:isSame(i, mail)
  local _, _, sender, subject, _, cod = try(self.env.GetInboxHeaderInfo, i)
  return sender == mail.sender and subject == mail.subject and (cod or 0) == (mail.cod or 0)
end

-- The takes go through the game's own calls, which the Ledger hooks (Game/LedgerAPI.lua).
-- Take all: AutoLootMailItem takes the money and every item in one go, like a shift-click in Blizzard's inbox.
-- Without it, one take per click: the money first, then the first item.
function MailAPI:takeAll(mail)
  local env, i = self.env, mail.index
  if (mail.cod or 0) > 0 then return false end -- paying needs the player's yes (payCOD)
  if type(env.AutoLootMailItem) == "function" then
    try(env.AutoLootMailItem, i)
    return true
  end
  if (mail.money or 0) > 0 then
    try(env.TakeInboxMoney, i)
    return true
  end
  for slot = 1, MailAPI.ATTACHMENTS do
    if try(env.GetInboxItem, i, slot) then
      try(env.TakeInboxItem, i, slot)
      return true
    end
  end
  return false
end

function MailAPI:takeItem(mail, slot)
  if (mail.cod or 0) > 0 then return false end
  try(self.env.TakeInboxItem, mail.index, slot)
  return true
end

-- Paying a COD: taking an item pays the amount; the rest are free to take after. slot: the item to take first,
-- else the first one.
function MailAPI:payCOD(mail, slot)
  if not self:isSame(mail.index, mail) then return false end
  if slot and try(self.env.GetInboxItem, mail.index, slot) then
    try(self.env.TakeInboxItem, mail.index, slot)
    return true
  end
  for s = 1, MailAPI.ATTACHMENTS do
    if try(self.env.GetInboxItem, mail.index, s) then
      try(self.env.TakeInboxItem, mail.index, s)
      return true
    end
  end
  return false
end

-- Collect's single takes (Game/MailCollector.lua): it never plans COD mail.
function MailAPI:takeMoney(index)
  try(self.env.TakeInboxMoney, index)
end

function MailAPI:takeSlot(index, slot)
  try(self.env.TakeInboxItem, index, slot)
end

-- Is the game still busy with the last mail command? Then the next take waits.
function MailAPI:commandPending()
  local c = self.env.C_Mail
  return c and type(c.IsCommandPending) == "function" and try(c.IsCommandPending) and true or false
end

function MailAPI:setOpeningAll(on)
  local c = self.env.C_Mail
  if c and type(c.SetOpeningAll) == "function" then try(c.SetOpeningAll, on) end
end

function MailAPI:returnMail(mail)
  try(self.env.ReturnInboxItem, mail.index)
end

-- Only an empty mail is deleted: the header is read again, so a mail that changed under the click is kept.
function MailAPI:deleteMail(mail)
  local _, _, sender, subject, money, _, _, items = try(self.env.GetInboxHeaderInfo, mail.index)
  if sender ~= mail.sender or subject ~= mail.subject or (money or 0) > 0 or (tonumber(items) or 0) > 0 then
    return false
  end
  try(self.env.DeleteInboxItem, mail.index)
  return true
end

function MailAPI:blizzardFrame()
  return self.env.MailFrame
end

-- Hide Blizzard's frame without Hide(): its OnHide closes the mailbox. Like the auction house window (#107),
-- conceal it as soon as it shows, so it is never drawn for a frame.
function MailAPI:concealBlizzard()
  local frame = self:blizzardFrame()
  if not frame then return end
  if not self.hooked and frame.HookScript then
    self.hooked = true
    frame:HookScript("OnShow", function()
      if self:replacing() then self:concealBlizzard() end
    end)
  end
  if self.concealed then return end
  self.concealed = { alpha = frame:GetAlpha(), scale = frame:GetScale(), mouse = frame:IsMouseEnabled() }
  frame:SetAlpha(0)
  frame:SetScale(0.001)
  frame:EnableMouse(false)
end

function MailAPI:revealBlizzard()
  local frame, saved = self:blizzardFrame(), self.concealed
  if not (frame and saved) then return end
  frame:SetAlpha(saved.alpha)
  frame:SetScale(saved.scale)
  frame:EnableMouse(saved.mouse)
  self.concealed = nil
end

function MailAPI:closeMail()
  try(self.env.CloseMail)
end

-- Free bag slots, or nil if the client can't say.
function MailAPI:freeSlots()
  local c = self.env.C_Container
  if c and type(c.CalculateTotalNumberOfFreeBagSlots) == "function" then
    return try(c.CalculateTotalNumberOfFreeBagSlots)
  end
  local get = c and c.GetContainerNumFreeSlots or self.env.GetContainerNumFreeSlots
  if type(get) ~= "function" then return nil end
  local free = 0
  for bag = 0, 4 do free = free + (try(get, bag) or 0) end
  return free
end

-- handlers: onOpen(mails), onInbox(mails), onClose(), onFailed(itemID), onCancelled(). Only while replacing
-- Blizzard's frame.
function MailAPI:onEvent(event, handlers, ...)
  if event == "MAIL_SHOW" then
    if not self:replacing() then
      self:revealBlizzard()
      return
    end
    self:concealBlizzard()
    self.open = true
    -- If ours can't open, give the player Blizzard's frame rather than an invisible mailbox.
    local ok, err = pcall(function()
      if handlers.onOpen then handlers.onOpen(self:readInbox(true)) end
    end)
    if not ok then
      self.open = false
      self:revealBlizzard()
      error(err, 0)
    end
  elseif event == "MAIL_INBOX_UPDATE" then
    if self.open and handlers.onInbox then handlers.onInbox(self:readInbox()) end
  elseif event == "MAIL_FAILED" then
    if self.open and handlers.onFailed then handlers.onFailed(...) end
  elseif event == "MAIL_OPEN_ALL_CANCELED" then
    if self.open and handlers.onCancelled then handlers.onCancelled() end
  elseif event == "MAIL_CLOSED" then
    local was = self.open
    self.open = false
    self:revealBlizzard()
    if was and handlers.onClose then handlers.onClose() end
  end
end

-- The Mailbox window (UI/MailboxWindow.lua) wires the events; this only makes the adapter it uses.
function MailAPI.install(env, addon)
  local api = MailAPI.new(env, addon)
  addon.mailAPI = api
  return api
end

ns.MailAPI = MailAPI
return MailAPI
