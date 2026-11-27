-- The Mailbox window's new mail (#158): the Send tab's side panel. To (typed, or picked from your characters),
-- subject, message, up to 12 items (alt-click them in your bags, or drop one on a slot; right-click a slot to
-- take it back), gold or a COD amount, the postage, and Send. Rules in Core/MailSend.lua; game calls in
-- Game/MailAPI.lua. Layout follows the Send artboard of the mockup linked from #149.
--
-- Needs the client to check: alt-click attaches with Blizzard's bags and with bag addons; the attachment
-- slots fill while Blizzard's own send frame is hidden; a send, a COD, and the error text when one fails.
local _, ns = ...
ns = ns or {}

local MailSendPanel = {}
MailSendPanel.__index = MailSendPanel

MailSendPanel.HINT = "Items (%d of %d)  ·  alt-click bag items"
MailSendPanel.SENT = "Sent to %s."
MailSendPanel.FAILED = "Not sent: %s"
MailSendPanel.FAILED_PLAIN = "Not sent. The game refused the mail."
MailSendPanel.SLOT_TIP = "Alt-click an item in your bags to add it, or drop one here. Right-click takes it back."
MailSendPanel.NO_ANSWER = "No answer from the game. Check your sent items before sending again."
MailSendPanel.COLLECTING = "Collect is running. Send once it is done."
MailSendPanel.TIMEOUT = 30 -- seconds without MAIL_SEND_SUCCESS or MAIL_FAILED before Send comes back
local SLOT, SLOT_STEP, PER_ROW, LIST_MAX = 30, 36, 6, 10

local function money(copper) return ns.Money.format(copper) end

-- window: the Mailbox window (for env, api, addon, and switching tabs).
function MailSendPanel.new(window)
  return setmetatable({ window = window, env = window.env, api = window.api, draft = { mode = "money" } },
    MailSendPanel)
end

local function input(env, parent, width)
  local e = env.CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(width, 20)
  e:SetAutoFocus(false)
  return e
end

function MailSendPanel:build(parent, inner)
  local env = self.env
  local p = env.CreateFrame("Frame", nil, parent)
  p:SetAllPoints(parent)
  self.frame = p
  local function text(font, y, x, w)
    local fs = p:CreateFontString(nil, "OVERLAY", font)
    fs:SetPoint("TOPLEFT", p, "TOPLEFT", x or 12, y)
    fs:SetWidth(w or inner)
    fs:SetJustifyH("LEFT")
    return fs
  end
  self.title = text("GameFontNormal", -12)
  self.title:SetText("New mail")

  text("GameFontNormalSmall", -34):SetText("To")
  self.to = input(env, p, inner - 30)
  self.to:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -48)
  self.to:SetScript("OnTextChanged", function(e) self:setTo(e:GetText()) end)
  local pick = env.CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  pick:SetSize(24, 22)
  pick:SetPoint("TOPLEFT", p, "TOPLEFT", 12 + inner - 24, -47)
  pick:SetText("v")
  pick:SetScript("OnClick", function() self:toggleList() end)
  ns.Window.tooltip(env, pick, "Your characters", "Pick one of your characters on this faction.")
  self.pick = pick

  text("GameFontNormalSmall", -74):SetText("Subject")
  self.subject = input(env, p, inner - 6)
  self.subject:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -88)
  if self.subject.SetMaxLetters then self.subject:SetMaxLetters(64) end -- the game's limit, as Blizzard's box
  if self.to.SetMaxLetters then self.to:SetMaxLetters(48) end
  self.subject:SetScript("OnTextChanged", function(e) self.draft.subject = e:GetText() end)

  text("GameFontNormalSmall", -114):SetText("Message")
  local body = env.CreateFrame("EditBox", nil, p, "InputBoxTemplate")
  body:SetSize(inner - 6, 44)
  body:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -128)
  body:SetAutoFocus(false)
  if body.SetMultiLine then body:SetMultiLine(true) end
  if body.SetMaxLetters then body:SetMaxLetters(500) end
  body:SetScript("OnTextChanged", function(e) self.draft.body = e:GetText() end)
  self.body = body
  -- Tab moves on, Escape lets go of the keyboard.
  local order = { self.to, self.subject, body }
  for i, box in ipairs(order) do
    box:SetScript("OnTabPressed", function() order[i % #order + 1]:SetFocus() end)
    box:SetScript("OnEscapePressed", function(e) e:ClearFocus() end)
  end

  self.itemsLabel = text("GameFontNormalSmall", -180)
  self.slots = {}
  for i = 1, ns.MailSend.MAX_ATTACH do
    local b = env.CreateFrame("Button", nil, p)
    b:SetSize(SLOT, SLOT)
    local col, row = (i - 1) % PER_ROW, math.floor((i - 1) / PER_ROW)
    b:SetPoint("TOPLEFT", p, "TOPLEFT", 12 + col * SLOT_STEP, -196 - row * SLOT_STEP)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetColorTexture(0, 0, 0, 0.45)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 2)
    if b.RegisterForClicks then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    b:SetScript("OnClick", function(_, button) self:clickSlot(i, button) end)
    if b.SetScript then b:SetScript("OnReceiveDrag", function() self:clickSlot(i, "LeftButton") end) end
    ns.Window.tooltip(env, b, "Attachment", MailSendPanel.SLOT_TIP)
    self.slots[i] = b
  end

  local y = -196 - 2 * SLOT_STEP - 6
  self.modes = {}
  for i, m in ipairs({ { "money", "Send gold" }, { "cod", "COD" } }) do
    local c = env.CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    c:SetSize(20, 20)
    c:SetPoint("TOPLEFT", p, "TOPLEFT", 8 + (i - 1) * 84, y + 3)
    local label = c.Text
    if not label then
      label = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      label:SetPoint("LEFT", c, "RIGHT", 1, 0)
    end
    label:SetText(m[2])
    c:SetScript("OnClick", function() self:setMode(m[1]) end)
    self.modes[m[1]] = c
  end
  self.amount = input(env, p, 76)
  self.amount:SetPoint("TOPLEFT", p, "TOPLEFT", 12 + inner - 76, y)
  self.amount:SetScript("OnTextChanged", function(e) self.draft.amount = e:GetText() end)
  ns.Window.tooltip(env, self.amount, "Amount", "Gold as 5g 20s, or a number of gold.")

  self.postage = text("GameFontHighlightSmall", y - 26)
  self.status = text("GameFontHighlightSmall", y - 44)
  if self.status.SetSpacing then self.status:SetSpacing(2) end

  local send = env.CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  send:SetSize(inner, 28)
  send:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 12, 12)
  send:SetText("Send")
  send:SetScript("OnClick", function() self:send() end)
  self.sendButton = send

  -- Your characters, under the To box while open.
  local list = env.CreateFrame("Frame", nil, p)
  list:EnableMouse(true) -- clicks between the names stay on the list
  list:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -70)
  list:SetSize(inner - 4, LIST_MAX * 18 + 8)
  list:SetFrameLevel(p:GetFrameLevel() + 10)
  local listBg = list:CreateTexture(nil, "BACKGROUND")
  listBg:SetAllPoints(list)
  listBg:SetColorTexture(0.05, 0.04, 0.03, 0.95)
  self.list, self.listButtons = list, {}
  for i = 1, LIST_MAX do
    local b = ns.Window.entryButton(env, list, inner - 12)
    b:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -4 - (i - 1) * 18)
    b:SetScript("OnClick", function() self:pickRecipient(b.name) end)
    self.listButtons[i] = b
  end
  list:Hide()
  return p
end

function MailSendPanel:shown()
  return self.frame and self.frame:IsShown() and self.window.frame and self.window.frame:IsShown()
end

function MailSendPanel:recipients()
  local env, chars = self.env, self.window.addon.characters
  local me = env.UnitName and env.UnitName("player")
  local faction = env.UnitFactionGroup and env.UnitFactionGroup("player")
  local guid = env.UnitGUID and env.UnitGUID("player")
  local server = type(guid) == "string" and guid:match("^Player%-(%d+)%-") or nil
  return ns.MailSend.recipients(chars and chars:characters() or {}, me, faction, server)
end

-- A changed recipient is a new mail, no longer a reply.
function MailSendPanel:setTo(text)
  self.draft.to = text
  if self.draft.replyMail and text ~= self.draft.replyMail.sender then self.draft.replyMail = nil end
end

-- Mailbox opened or closed: a send still waiting for its answer is over, as is a reply to this visit's mail.
function MailSendPanel:reset()
  self.sending, self.lastError, self.draft.replyMail = nil, nil, nil
  if self.list then self.list:Hide() end
  self:render()
end

function MailSendPanel:toggleList()
  if self.list:IsShown() then return self.list:Hide() end
  local names = self:recipients()
  for i, b in ipairs(self.listButtons) do
    b.name = names[i]
    b:SetShown(names[i] ~= nil)
    if names[i] then b:SetText(names[i]) end
  end
  if #names > 0 then self.list:Show() end
end

function MailSendPanel:pickRecipient(name)
  if not name then return end
  self.to:SetText(name)
  self:setTo(name)
  self.list:Hide()
end

function MailSendPanel:setMode(mode)
  self.draft.mode = mode
  self:render()
end

-- Like Blizzard's slots: right-click takes the item back, a click drops the cursor's item or picks this one up.
function MailSendPanel:clickSlot(i, button)
  local item = self.items and self.items[i]
  if button == "RightButton" then
    if item then self.api:detach(item.slot) end
  elseif self.api:cursorHasItem() then
    self.api:dropOnMail()
  elseif item then
    self.api:dropOnMail(item.slot)
  end
end

-- An alt-clicked bag item, while this panel is in view.
function MailSendPanel:attachFromBag(bag, slot)
  if not self:shown() then return end
  self.api:attachFromBag(bag, slot)
end

-- Reply on an open letter: the sender and "Re:" filled in.
function MailSendPanel:reply(mail)
  self.draft = { mode = "money", to = mail.sender or "", subject = ns.MailSend.reSubject(mail.subject),
    replyMail = mail }
  self.to:SetText(self.draft.to)
  self.subject:SetText(self.draft.subject)
  self.body:SetText("")
  self.amount:SetText("")
  self.message = nil
end

function MailSendPanel:collecting()
  local c = self.window.collector
  return c and c:running()
end

function MailSendPanel:send()
  if self.sending then return end
  local api = self.api
  -- Collect's takes and a send would share MAIL_FAILED.
  if self:collecting() then
    self.message = MailSendPanel.COLLECTING
    return self:render()
  end
  local mail, why = ns.MailSend.check(self.draft, self.items or api:sendItems(),
    { codEnabled = api:codEnabled(), money = api:playerMoney(), postage = api:postage() })
  if not mail then
    self.message = "|cffff6060" .. why .. "|r"
    return self:render()
  end
  -- A reply names the mail it answers by its inbox index, which moves as mail comes and goes.
  local reply = self.draft.replyMail
  local replyTo = reply and reply.index and api:isSame(reply.index, reply) and reply.index or nil
  self.sending, self.lastError, self.message = mail, nil, nil
  self.sendButton:Disable()
  api:send(mail, replyTo)
  local timer, sending = self.env.C_Timer, mail
  if timer then
    timer.After(MailSendPanel.TIMEOUT, function()
      if self.sending == sending then
        self.sending = nil
        self.message = MailSendPanel.NO_ANSWER
        self:render()
      end
    end)
  end
  self:render()
end

function MailSendPanel:onSent()
  local mail = self.sending
  if not mail then return self:render() end -- another addon's send: keep the half-written mail
  self.sending = nil
  -- Blizzard's own (hidden) send frame resets on the same event and may give its To box the keyboard.
  local blizz = self.env.SendMailNameEditBox
  if blizz and blizz.HasFocus and blizz:HasFocus() then blizz:ClearFocus() end
  self.draft = { mode = "money" }
  self.to:SetText("")
  self.subject:SetText("")
  self.body:SetText("")
  self.amount:SetText("")
  self.message = mail and string.format(MailSendPanel.SENT, mail.to) or nil
  self:render()
end

function MailSendPanel:onError(message)
  if self.sending and type(message) == "string" then self.lastError = message end
end

-- MAIL_FAILED: true when it was this panel's send that failed.
function MailSendPanel:onFailed()
  if not self.sending then return false end
  self.sending = nil
  self.message = "|cffff6060" .. (self.lastError and string.format(MailSendPanel.FAILED, self.lastError)
    or MailSendPanel.FAILED_PLAIN) .. "|r"
  self:render()
  return true
end

function MailSendPanel:render()
  if not self.frame then return end
  local api = self.api
  local items = api:sendItems()
  self.items = items
  self.itemsLabel:SetText(string.format(MailSendPanel.HINT, #items, ns.MailSend.MAX_ATTACH))
  for i, b in ipairs(self.slots) do
    local a = items[i]
    b.icon:SetShown(a ~= nil)
    b.count:SetText(a and a.count > 1 and tostring(a.count) or "")
    if a then b.icon:SetTexture(a.texture or "Interface\\Icons\\INV_Misc_QuestionMark") end
  end
  local cod = api:codEnabled()
  if not cod and self.draft.mode == "cod" then self.draft.mode = "money" end
  for id, c in pairs(self.modes) do c:SetChecked(self.draft.mode == id) end
  self.modes.cod:SetEnabled(cod)
  local postage = api:postage()
  local line = "Postage " .. money(postage)
  local have = api:playerMoney()
  if have and postage > have then line = "|cffff6060" .. line .. "|r" end
  self.postage:SetText(line)
  self.status:SetText(self.message or "")
  self.sendButton:SetEnabled(not self.sending and not self:collecting())
  self.sendButton:SetText(self.sending and "Sending..." or "Send")
  if self.list and not self:shown() then self.list:Hide() end
end

ns.MailSendPanel = MailSendPanel
return MailSendPanel
