-- The Settings view (#87): settings that apply to every character and market. The first is the default
-- posting duration, kept by Posting.Settings in BetterAHDB.posting. Layout follows the mockup linked
-- from issue #87. This file only draws and wires; the rules live in Core/Posting.lua.
local _, ns = ...
ns = ns or {}

local SettingsView = {}
SettingsView.__index = SettingsView

SettingsView.DETAIL = {
  title = "Default duration",
  body = "How long a new item's auctions run, until you give the item its own duration in the Post view.\n\n"
    .. "Items you gave their own duration keep it. Changing this doesn't change them.\n\n"
    .. "The Post view's duration buttons start on this value for an item without a profile.",
}

function SettingsView.new(window, addon)
  return setmetatable({ window = window, env = window.env, addon = addon }, SettingsView)
end

function SettingsView:build(f, x, y, width, height)
  local env = self.env
  local panel = env.CreateFrame("Frame", nil, f)
  panel:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
  panel:SetSize(width, height)
  self.panel = panel

  local note = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
  note:SetText("These apply to every character and market.")
  self.note = note

  local group = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  group:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -24)
  group:SetText("Posting")
  self.groupLabel = group

  local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -52)
  label:SetText("Default duration")
  self.durationLabel = label

  self.durationButtons = {}
  for i in ipairs(ns.Posting.DURATIONS) do
    local text = ns.PostView.durationLabel(env, i)
    local b = env.CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(72, 22)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", 150 + (i - 1) * 76, -47)
    b:SetText(text)
    b:SetScript("OnClick", function() self:setDuration(i) end)
    ns.Window.tooltip(env, b, text, "Post new items for " .. text .. " unless they have their own duration.")
    self.durationButtons[i] = b
  end

  self:buildDebug(panel)
  self:buildTooltips(panel)
  self:buildMail(panel)

  -- On the shared detail panel, so shown only while this view is.
  local w = self.window
  local reset = env.CreateFrame("Button", nil, w.detailLayer, "UIPanelButtonTemplate")
  reset:SetHeight(22)
  reset:SetPoint("BOTTOMLEFT", w.detailLayer, "BOTTOMLEFT", 12, 12)
  reset:SetPoint("BOTTOMRIGHT", w.detailLayer, "BOTTOMRIGHT", -12, 12)
  local default = ns.PostView.durationLabel(env, ns.Posting.DEFAULT_DURATION)
  reset:SetText("Reset to " .. default)
  reset:SetScript("OnClick", function() self:setDuration(ns.Posting.DEFAULT_DURATION) end)
  ns.Window.tooltip(env, reset, "Reset to " .. default, "Go back to the default duration of " .. default .. ".")
  reset:Hide()
  self.resetButton = reset
  return panel
end

-- The debug log (#99): off or on, in the same style as the duration buttons.
SettingsView.DEBUG_NOTE = "Keeps a log of what you do in Better AH and what the auction house answers, "
  .. "for bug reports. It's saved on /reload or logout. Type /bah mark and a note to flag a moment."

function SettingsView:buildDebug(panel)
  local env = self.env
  local group = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  group:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -88)
  group:SetText("Debugging")
  self.debugGroupLabel = group

  local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -116)
  label:SetText("Debug log")
  self.debugLabel = label

  self.debugButtons = {}
  for i, spec in ipairs({ { false, "Off", "Don't keep a debug log." },
    { true, "On", "Log what you do and what the auction house answers, for bug reports." } }) do
    local b = env.CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(72, 22)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", 150 + (i - 1) * 76, -111)
    b:SetText(spec[2])
    b:SetScript("OnClick", function() self:setDebug(spec[1]) end)
    ns.Window.tooltip(env, b, "Debug log " .. spec[2]:lower(), spec[3])
    b.debugValue = spec[1]
    self.debugButtons[i] = b
  end

  local note = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  note:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -142)
  note:SetWidth(380)
  note:SetJustifyH("LEFT")
  note:SetText(SettingsView.DEBUG_NOTE)
  self.debugNote = note
end

-- Tooltips (#119): what Better AH adds to item tooltips, each part on unless turned off.
SettingsView.TOOLTIPS_TOP = -196

function SettingsView:buildTooltips(panel)
  local env = self.env
  local group = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  group:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, SettingsView.TOOLTIPS_TOP)
  group:SetText("Tooltips")
  self.tooltipGroupLabel = group

  self.tooltipChecks = {}
  for i, s in ipairs(ns.TooltipPrices.SETTINGS) do
    local b = env.CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    b:SetSize(24, 24)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", s.sub and 28 or 4, SettingsView.TOOLTIPS_TOP - 20 - (i - 1) * 24)
    b:SetScript("OnClick", function(c) self:setTooltip(s.key, c:GetChecked() and true or false) end)
    ns.Window.tooltip(env, b, s.label, s.tip)
    local label = b.Text
    if not label then
      label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      label:SetPoint("LEFT", b, "RIGHT", 2, 0)
    end
    label:SetText(s.label)
    if b.SetHitRectInsets then b:SetHitRectInsets(0, -260, 0, 0) end
    b.settingKey, b.label = s.key, label
    self.tooltipChecks[i] = b
  end
end

-- Mail (#154): the Mailbox window replaces Blizzard's mail frame unless this is off.
SettingsView.MAIL_TOP = -320
SettingsView.MAIL = { label = "Replace Blizzard's mail frame with the Better AH Mailbox",
  tip = "Off: mailboxes open Blizzard's own mail frame again. Takes effect the next time you open a mailbox." }

function SettingsView:buildMail(panel)
  local env = self.env
  local group = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  group:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, SettingsView.MAIL_TOP)
  group:SetText("Mail")
  self.mailGroupLabel = group
  local b = env.CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  b:SetSize(24, 24)
  b:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, SettingsView.MAIL_TOP - 16)
  b:SetScript("OnClick", function(c) self:setMailReplace(c:GetChecked() and true or false) end)
  ns.Window.tooltip(env, b, SettingsView.MAIL.label, SettingsView.MAIL.tip)
  local label = b.Text
  if not label then
    label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", b, "RIGHT", 2, 0)
  end
  label:SetText(SettingsView.MAIL.label)
  if b.SetHitRectInsets then b:SetHitRectInsets(0, -320, 0, 0) end
  self.mailCheck = b
end

-- Stored as replace = false only when off, so a missing value means on.
function SettingsView:setMailReplace(on)
  local saved = self.addon.mailSettings
  if type(saved) == "table" then
    if on then saved.replace = nil else saved.replace = false end
  end
  self:render()
end

function SettingsView:setTooltip(key, on)
  local saved = self.addon.tooltipSettings
  if saved then ns.TooltipPrices.set(saved, key, on) end
  self:render()
end

function SettingsView:setDebug(on)
  if ns.DebugHooks then ns.DebugHooks.setOn(self.env, on) end
  self:render()
end

function SettingsView:setDuration(index)
  local settings = self.addon.posting
  if settings and settings:setDefaultDuration(index) then self:render() end
end

function SettingsView:hide()
  if self.resetButton then self.resetButton:Hide() end
end

function SettingsView:render()
  if not (self.panel and self.panel:IsShown()) then return end
  local w, settings = self.window, self.addon.posting
  w.detailTitle:SetText(SettingsView.DETAIL.title)
  w.detailBody:SetText(settings and SettingsView.DETAIL.body or "Settings aren't loaded yet.")
  local current = settings and settings:defaultDuration()
  for i, b in ipairs(self.durationButtons) do
    if i == current then b:LockHighlight() else b:UnlockHighlight() end
    if settings then b:Enable() else b:Disable() end
  end
  local log = ns.debugLog
  for _, b in ipairs(self.debugButtons or {}) do
    if log and log:isOn() == b.debugValue then b:LockHighlight() else b:UnlockHighlight() end
    if log then b:Enable() else b:Disable() end
  end
  local saved = self.addon.tooltipSettings
  local opts = ns.TooltipPrices.options(saved)
  for _, b in ipairs(self.tooltipChecks or {}) do
    b:SetChecked(opts[b.settingKey])
    -- The parts only matter while the tooltip block is on.
    local usable = saved ~= nil and (b.settingKey == "show" or opts.show)
    if usable then b:Enable() else b:Disable() end
    -- Disable() doesn't grey a check button's label: grey it here, so a part that waits looks it.
    if b.label and b.label.SetTextColor then
      if usable then b.label:SetTextColor(1, 1, 1) else b.label:SetTextColor(0.5, 0.5, 0.5) end
    end
  end
  if self.mailCheck then
    local mail = self.addon.mailSettings
    self.mailCheck:SetChecked(not (type(mail) == "table" and mail.replace == false))
    if type(mail) == "table" then self.mailCheck:Enable() else self.mailCheck:Disable() end
  end
  self.resetButton:SetShown(settings ~= nil)
  if current and current ~= ns.Posting.DEFAULT_DURATION then self.resetButton:Enable()
  else self.resetButton:Disable() end
end

ns.SettingsView = SettingsView
return SettingsView
