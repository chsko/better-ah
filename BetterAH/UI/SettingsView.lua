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
  self.resetButton:SetShown(settings ~= nil)
  if current and current ~= ns.Posting.DEFAULT_DURATION then self.resetButton:Enable()
  else self.resetButton:Disable() end
end

ns.SettingsView = SettingsView
return SettingsView
