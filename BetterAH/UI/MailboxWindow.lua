-- The Mailbox window (#149, #154): Better AH's own window, separate from the auction house window, shown instead
-- of Blizzard's mail frame at a mailbox. Inbox lists every mail with its kind (Core/Mailbox.lua); Send comes in
-- later tickets. Layout follows the mockup linked from #149. Game calls go through Game/MailAPI.lua.
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
MailboxWindow.SEND_EMPTY = "Send rules, Send all and new mail come here."
MailboxWindow.EMPTY = "No mail."

function MailboxWindow.new(env, addon)
  local self = setmetatable({ env = env, addon = addon or {}, rows = {}, offset = 0, tab = "inbox" }, MailboxWindow)
  self.api = self.addon.mailAPI or ns.MailAPI.install(env, self.addon)
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

  local sendNote = text:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  sendNote:SetPoint("TOPLEFT", f, "TOPLEFT", 20, TOP - 20)
  sendNote:SetText(MailboxWindow.SEND_EMPTY)
  self.sendNote = sendNote

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

  if ns.WindowResize and ns.WindowScale then
    local db = self.addon.db
    local saved = db and db.mailWindow or {}
    if db then db.mailWindow = saved end
    self.resize = ns.WindowResize.attach(env, f, WIDTH, HEIGHT, saved, Window.tooltip)
  end
  self:render()
  return f
end

function MailboxWindow:selectTab(id)
  self.tab = id
  self:render()
end

function MailboxWindow.clickRow() end -- opening a mail comes with #155

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
  self:scrollTo(self.offset)
  self:render()
end

function MailboxWindow:open(mails)
  self:build()
  self.offset = 0
  self.tab = "inbox"
  self:setMails(mails)
  self.frame:Show()
end

function MailboxWindow:close()
  if not self.frame then return end
  self.closing = true
  self.frame:Hide()
  self.closing = nil
end

local function money(copper)
  return ns.Money.format(copper)
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
    for c = 1, #MailboxWindow.COLUMNS do r[c]:SetText(cells and cells[c] or "") end
  end
  ns.Window.syncScrollBar(self.listRows.scrollBar, self.offset, inbox and #self.rows or 0)
end

-- The detail panel while no mail is open: what the inbox holds, per kind.
function MailboxWindow.summaryText(totals)
  local lines = {}
  for _, k in ipairs(ns.Mailbox.KINDS) do
    local t = totals[k.id]
    if t.mails > 0 then
      local holds = {}
      if t.gold > 0 then holds[#holds + 1] = money(t.gold) end
      if t.items > 0 then holds[#holds + 1] = t.items == 1 and "1 item" or (t.items .. " items") end
      lines[#lines + 1] = string.format("%s: %d%s", k.label, t.mails,
        #holds > 0 and ("  (" .. table.concat(holds, ", ") .. ")") or "")
    end
  end
  if #lines == 0 then return MailboxWindow.EMPTY end
  if totals.expiring > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("|cffff9a3c%d expire in under %d days.|r Expired auction mail loses its items.",
      totals.expiring, ns.Mailbox.EXPIRING_DAYS)
  end
  return table.concat(lines, "\n")
end

function MailboxWindow.footer(totals)
  local n = totals.mails
  local s = n == 1 and "1 mail" or (n .. " mails")
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
  self.sendNote:SetShown(not inbox)
  self.emptyText:SetText(inbox and #self.rows == 0 and MailboxWindow.EMPTY or "")
  self.footerText:SetText(MailboxWindow.footer(totals))
  local name = self.env.UnitName and self.env.UnitName("player")
  local free = self.api:freeSlots()
  self.statusText:SetText((name or "") .. (free and string.format("  ·  bags %d free", free) or ""))
  if inbox then
    self.detailTitle:SetText("In this inbox")
    self.detailBody:SetText(MailboxWindow.summaryText(totals))
  else
    self.detailTitle:SetText("Send")
    self.detailBody:SetText(MailboxWindow.SEND_EMPTY)
  end
  self:renderRows()
end

function MailboxWindow:onEvent(event)
  self.api:onEvent(event, {
    onOpen = function(mails) self:open(mails) end,
    onInbox = function(mails) self:setMails(mails) end,
    onClose = function() self:close() end,
  })
end

function MailboxWindow.install(env, addon)
  local w = MailboxWindow.new(env, addon)
  local events = env.CreateFrame("Frame")
  for _, e in ipairs(ns.MailAPI.EVENTS) do events:RegisterEvent(e) end
  events:SetScript("OnEvent", function(_, event) w:onEvent(event) end)
  addon.mailboxWindow = w
  return w
end

ns.MailboxWindow = MailboxWindow
if ns.MailAPI and ns.Mailbox and CreateFrame then MailboxWindow.install(_G, ns) end
return MailboxWindow
