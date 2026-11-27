-- The Send tab's main area (#159): the send rules, what each would send now, the rule editor, and Send all.
-- Rules in Core/SendRules.lua, saved per account in BetterAHDB.mail.rules; the run is Game/MailSender.lua.
-- Layout follows the Send artboard of the mockup linked from #149.
--
-- Needs the client to check: alt-click picks a bag item for an item rule; the list and footer fit; a Send all;
-- the bottom bar level with the new mail's Send; the editor under 8 rules clear of the last-run line.
local _, ns = ...
ns = ns or {}

local MailRulesPanel = {}
MailRulesPanel.__index = MailRulesPanel

MailRulesPanel.COLUMNS = {
  { "Items", 4, 150, "LEFT" }, { "Matches", 158, 70, "LEFT" }, { "To", 232, 90, "LEFT" }, { "Keep", 326, 40 },
  { "Sends", 370, 60 },
}
MailRulesPanel.ROWS = 8
MailRulesPanel.EMPTY = "No send rules yet. A rule sends an item, a disenchant group or a type of item to one of " ..
  "your characters whenever you press Send all."
MailRulesPanel.HINT = "Click a rule to change it."
MailRulesPanel.MORE = "Rules %d-%d of %d: scroll for the rest. Click a rule to change it."
MailRulesPanel.PICK_ITEM = "Alt-click an item in your bags."
MailRulesPanel.KEEP_TIP = "How many of each item stay in your bags. Leave it empty to send them all. " ..
  "Whole stacks go, so a few more may stay."
MailRulesPanel.SEND_ALL_TIP = "Sends every rule's items now, one mail at a time, then says what went out."
MailRulesPanel.COLLECTING = "Collect is running. Send all once it is done."
MailRulesPanel.MAIL_BUSY = "Send or empty the new mail first: Send all uses the same attachment slots."
MailRulesPanel.NOTHING = "Nothing to send: no rule matches what is in your bags."
MailRulesPanel.SENDING = "Sending mail %d of %d..."
MailRulesPanel.STOPPING = "Stopping once the game answers the mail on its way..."
local ROW_HEIGHT = 18
-- The bottom bar: "+ Add rule", the footer and Send all, level with the new mail's Send button.
local BAR_Y, BAR_HEIGHT = 12, 28

-- Where the hint and the rule editor start: just under the last rule shown (Window.buildRows puts row r's top at
-- -32 - r * 18 + 3), or under the empty-list text.
function MailRulesPanel.belowList(shown)
  if shown == 0 then return -100 end
  return -55 - shown * ROW_HEIGHT
end

local MATCHES = { { "item", "Item" }, { "group", "DE group" }, { "type", "Type" } }

-- window: the Mailbox window (env, api, addon, sendPanel, collector, sender).
function MailRulesPanel.new(window)
  return setmetatable({ window = window, env = window.env, api = window.api, offset = 0 }, MailRulesPanel)
end

-- The saved rules, BetterAHDB.mail.rules.
function MailRulesPanel:saved()
  local settings = self.window.addon.mailSettings
  if type(settings) ~= "table" then
    self.fallback = self.fallback or {}
    return self.fallback
  end
  if type(settings.rules) ~= "table" then settings.rules = {} end
  return settings.rules
end

function MailRulesPanel:me()
  local env = self.env
  return env.UnitName and env.UnitName("player") or nil
end

function MailRulesPanel:build(parent, width, height)
  local env = self.env
  local p = env.CreateFrame("Frame", nil, parent)
  p:SetSize(width, height)
  self.frame, self.width = p, width
  self.rows = setmetatable({ env = env }, { __index = ns.Window }):buildRows(p, MailRulesPanel.COLUMNS,
    function(r) self:clickRow(r) end, nil, width)
  for r = MailRulesPanel.ROWS + 1, #self.rows do
    self.rows[r].button:Hide()
    self.rows[r].hidden = true
  end
  if p.EnableMouseWheel then
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(_, delta) self:scrollTo(self.offset - delta) end)
  end
  local function text(font, y, x, w, justify)
    local fs = p:CreateFontString(nil, "OVERLAY", font)
    fs:SetPoint("TOPLEFT", p, "TOPLEFT", x or 4, y)
    fs:SetWidth(w or (width - 8))
    fs:SetJustifyH(justify or "LEFT")
    return fs
  end
  self.emptyText = text("GameFontDisable", -60)
  self.emptyText:SetText(MailRulesPanel.EMPTY)
  self.hintText = text("GameFontDisableSmall", MailRulesPanel.belowList(0))
  self.hintText:SetText(MailRulesPanel.HINT)
  self:buildEditor(p, width)

  local add = env.CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  add:SetSize(100, BAR_HEIGHT)
  add:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 2, BAR_Y)
  add:SetText("+ Add rule")
  add:SetScript("OnClick", function() self:edit(nil) end)
  self.addButton = add
  self.footer = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  self.footer:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 112, BAR_Y + 8)
  self.footer:SetWidth(width - 112 - 118)
  self.footer:SetJustifyH("LEFT")
  local all = env.CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  all:SetSize(110, BAR_HEIGHT)
  all:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -2, BAR_Y)
  all:SetText("Send all")
  all:SetScript("OnClick", function() self:clickSendAll() end)
  ns.Window.tooltip(env, all, "Send all", MailRulesPanel.SEND_ALL_TIP)
  self.sendAllButton = all
  self.lastText = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  self.lastText:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 4, BAR_Y + BAR_HEIGHT + 10)
  self.lastText:SetWidth(width - 8)
  self.lastText:SetJustifyH("LEFT")
  return p
end

local function input(env, parent, width)
  local e = env.CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(width, 20)
  e:SetAutoFocus(false)
  e:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
  return e
end

function MailRulesPanel:buildEditor(p, width)
  local env = self.env
  local ed = env.CreateFrame("Frame", nil, p)
  ed:SetPoint("TOPLEFT", p, "TOPLEFT", 4, MailRulesPanel.belowList(0))
  ed:SetSize(width, 140)
  self.editor = ed
  local function label(textValue, x, y)
    local fs = ed:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", ed, "TOPLEFT", x, y)
    fs:SetText(textValue)
    return fs
  end
  local function button(textValue, w, x, y, onClick)
    local b = env.CreateFrame("Button", nil, ed, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetPoint("TOPLEFT", ed, "TOPLEFT", x, y)
    b:SetText(textValue)
    b:SetScript("OnClick", onClick)
    return b
  end
  self.editTitle = label("New rule", 4, 0)
  label("Sends", 4, -26)
  self.matchButtons = {}
  for i, m in ipairs(MATCHES) do
    self.matchButtons[m[1]] = button(m[2], 80, 60 + (i - 1) * 84, -22, function() self:setMatch(m[1]) end)
  end
  self.prevButton = button("<", 24, 60, -48, function() self:cycle(-1) end)
  self.choiceText = ed:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  self.choiceText:SetPoint("TOPLEFT", ed, "TOPLEFT", 90, -52)
  self.choiceText:SetWidth(200)
  self.choiceText:SetJustifyH("LEFT")
  self.nextButton = button(">", 24, 296, -48, function() self:cycle(1) end)

  label("To", 4, -80)
  self.toBox = input(env, ed, 110)
  self.toBox:SetPoint("TOPLEFT", ed, "TOPLEFT", 66, -76)
  self.toBox:SetScript("OnTextChanged", function(e) if self.draft then self.draft.to = e:GetText() end end)
  self.toNext = button("v", 24, 180, -75, function() self:nextRecipient() end)
  ns.Window.tooltip(env, self.toNext, "Your characters", "Picks the next of your characters on this faction.")
  label("Keep", 220, -80)
  self.keepBox = input(env, ed, 50)
  self.keepBox:SetPoint("TOPLEFT", ed, "TOPLEFT", 260, -76)
  self.keepBox:SetScript("OnTextChanged", function(e) if self.draft then self.draft.keep = e:GetText() end end)
  ns.Window.tooltip(env, self.keepBox, "Keep", MailRulesPanel.KEEP_TIP)
  self.toBox:SetScript("OnTabPressed", function() self.keepBox:SetFocus() end)
  self.keepBox:SetScript("OnTabPressed", function() self.toBox:SetFocus() end)

  self.saveButton = button("Save", 80, 60, -104, function() self:save() end)
  self.cancelButton = button("Cancel", 80, 144, -104, function() self:closeEditor() end)
  self.deleteButton = button("Delete", 80, 228, -104, function() self:delete() end)
  self.editStatus = ed:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  self.editStatus:SetPoint("TOPLEFT", ed, "TOPLEFT", 4, -130)
  self.editStatus:SetWidth(width - 8)
  self.editStatus:SetJustifyH("LEFT")
  ed:Hide()
end

function MailRulesPanel:list()
  return ns.SendRules.new(self:saved())
end

-- Opens the editor on rule index (nil: a new rule).
function MailRulesPanel:edit(index)
  local rule = index and self:saved()[index]
  self.editing = rule and index or nil
  if rule then
    self.draft = { match = rule.match, itemID = rule.itemID, name = rule.name, group = rule.group, type = rule.type,
      to = rule.to, keep = rule.keep and tostring(rule.keep) or "" }
  else
    local names = self.window.sendPanel and self.window.sendPanel:recipients() or {}
    self.draft = { match = "item", group = "all", type = ns.SendRules.TYPES[1].id, to = names[1] or "", keep = "" }
  end
  self.editMessage = nil
  self.toBox:SetText(self.draft.to or "")
  self.keepBox:SetText(self.draft.keep or "")
  self:render()
end

function MailRulesPanel:closeEditor()
  self.draft, self.editing, self.editMessage = nil, nil, nil
  if self.toBox.ClearFocus then self.toBox:ClearFocus() end
  if self.keepBox.ClearFocus then self.keepBox:ClearFocus() end
  self:render()
end

function MailRulesPanel:clickRow(r)
  local index = self.offset + r
  if not self:saved()[index] then return end
  if self.editing == index then return self:closeEditor() end
  self:edit(index)
end

function MailRulesPanel:setMatch(match)
  if not self.draft then return end
  self.draft.match = match
  self:render()
end

local function choices(match)
  return match == "group" and ns.SendRules.GROUPS or ns.SendRules.TYPES
end

function MailRulesPanel:cycle(step)
  local d = self.draft
  if not d or d.match == "item" then return end
  local list, field = choices(d.match), d.match == "group" and "group" or "type"
  local at = 1
  for i, c in ipairs(list) do if c.id == d[field] then at = i end end
  d[field] = list[(at - 1 + step) % #list + 1].id
  self:render()
end

function MailRulesPanel:nextRecipient()
  local d = self.draft
  if not d then return end
  local names = self.window.sendPanel and self.window.sendPanel:recipients() or {}
  if #names == 0 then return end
  local at = 0
  for i, n in ipairs(names) do if n == d.to then at = i end end
  d.to = names[at % #names + 1]
  self.toBox:SetText(d.to)
end

-- An item rule waits for an alt-clicked bag item.
function MailRulesPanel:wantsItem()
  return self.draft ~= nil and self.draft.match == "item" and self.frame:IsShown()
end

-- stack: MailAPI:bagStack of the alt-clicked slot.
function MailRulesPanel:pickItem(stack)
  if not (self.draft and stack) then return end
  if stack.bound then
    self.editMessage = "|cffff6060That item is soulbound, so it can't be mailed.|r"
  else
    self.draft.itemID, self.draft.name, self.editMessage = stack.itemID, stack.name, nil
  end
  self:render()
end

function MailRulesPanel:save()
  local d = self.draft
  if not d then return end
  local list, opts = self:list(), { me = self:me() }
  local ok, why
  if self.editing then ok, why = list:update(self.editing, d, opts) else ok, why = list:add(d, opts) end
  if not ok then
    self.editMessage = "|cffff6060" .. why .. "|r"
    return self:render()
  end
  self:closeEditor()
end

function MailRulesPanel:delete()
  if not self.editing then return end
  self:list():remove(self.editing)
  self:closeEditor()
end

function MailRulesPanel:scrollTo(offset)
  local max = math.max(0, #self:saved() - MailRulesPanel.ROWS)
  self.offset = math.max(0, math.min(max, math.floor(offset or 0)))
  self:render()
end

function MailRulesPanel:sender()
  return self.window.sender
end

function MailRulesPanel:clickSendAll()
  local sender = self:sender()
  if not sender then return end
  if sender:running() then
    sender:stop()
    return self:render()
  end
  self.message = nil
  local collector, panel = self.window.collector, self.window.sendPanel
  if collector and collector:running() then
    self.message = MailRulesPanel.COLLECTING
  elseif (panel and panel.sending) or #self.api:sendItems() > 0 then
    self.message = MailRulesPanel.MAIL_BUSY
  elseif not sender:start(self:saved(), { me = self:me() }) then
    self.message = MailRulesPanel.NOTHING
  end
  self.window:render()
end

-- A Send all ended: its line here and in the chat.
function MailRulesPanel:done(run)
  self.message = nil
  self.last = run.summary
  local chat = self.env.DEFAULT_CHAT_FRAME
  if chat and chat.AddMessage then chat:AddMessage("|cfff2c94cBetter AH|r " .. run.summary) end
end

function MailRulesPanel:renderEditor()
  local d, ed = self.draft, self.editor
  ed:SetShown(d ~= nil)
  if not d then return end
  self.editTitle:SetText(self.editing and "Change rule" or "New rule")
  for id, b in pairs(self.matchButtons) do
    if id == d.match then b:LockHighlight() else b:UnlockHighlight() end
  end
  local item = d.match == "item"
  self.prevButton:SetShown(not item)
  self.nextButton:SetShown(not item)
  if item then
    self.choiceText:SetText(d.itemID and (d.name or ("item " .. d.itemID)) or MailRulesPanel.PICK_ITEM)
  else
    self.choiceText:SetText(ns.SendRules.label(d))
  end
  self.deleteButton:SetShown(self.editing ~= nil)
  self.editStatus:SetText(self.editMessage or "")
end

function MailRulesPanel:render()
  if not self.frame then return end
  local SendRules, rules = ns.SendRules, self:saved()
  local plan = SendRules.plan(rules, self.api:bagStacks(), { me = self:me() })
  self.plan = plan
  local max = math.max(0, #rules - MailRulesPanel.ROWS)
  if self.offset > max then self.offset = max end
  for r = 1, MailRulesPanel.ROWS do
    local row, index = self.rows[r], self.offset + r
    local rule = rules[index]
    row.button:SetShown(rule ~= nil)
    if row.button.selectedTexture then row.button.selectedTexture:SetShown(rule ~= nil and self.editing == index) end
    local cells = rule and { SendRules.label(rule), SendRules.kindLabel(rule), rule.to or "",
      rule.keep and tostring(rule.keep) or "0", SendRules.sendsText(plan.byRule[index]) } or {}
    for c = 1, #MailRulesPanel.COLUMNS do row[c]:SetText(cells[c] or "") end
  end
  self.emptyText:SetShown(#rules == 0 and not self.draft)
  self.hintText:SetShown(#rules > 0 and not self.draft)
  self.addButton:SetEnabled(not self.draft)
  -- The hint and the editor follow the list down.
  local below = MailRulesPanel.belowList(math.min(MailRulesPanel.ROWS, #rules))
  self.hintText:ClearAllPoints()
  self.hintText:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 4, below)
  self.editor:ClearAllPoints()
  self.editor:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 4, below)
  if #rules > MailRulesPanel.ROWS then
    self.hintText:SetText(string.format(MailRulesPanel.MORE, self.offset + 1,
      math.min(#rules, self.offset + MailRulesPanel.ROWS), #rules))
  else
    self.hintText:SetText(MailRulesPanel.HINT)
  end
  self:renderEditor()

  local sender = self:sender()
  local run = sender and sender.run
  local running = sender and sender:running()
  self.footer:SetText(SendRules.footer(plan))
  local busy = self.window.collector and self.window.collector:running()
  if running then
    self.sendAllButton:SetText("Stop")
    self.sendAllButton:SetEnabled(not run.stopping)
    self.lastText:SetText(run.stopping and MailRulesPanel.STOPPING
      or string.format(MailRulesPanel.SENDING, math.min(run.mails + 1, run.planned), run.planned))
  else
    self.sendAllButton:SetText("Send all")
    self.sendAllButton:SetEnabled(sender ~= nil and #plan.mails > 0 and not busy)
    self.lastText:SetText(self.message or (self.last and ("Last Send all: " .. self.last)) or "")
  end
end

ns.MailRulesPanel = MailRulesPanel
return MailRulesPanel
