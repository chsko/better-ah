-- A tiny fake of the WoW frame API: enough to drive the UI adapters in specs.
local M = {}

local Frame = {}
Frame.__index = Frame

local function newFrame(kind, name, parent, template)
  return setmetatable({
    kind = kind, name = name, parent = parent, template = template,
    shown = true, alpha = 1, scale = 1, mouse = true, scripts = {}, events = {},
    highlighted = false, text = nil,
  }, Frame)
end

function Frame:SetSize() end
function Frame:GetName() return self.name end
function Frame:GetParent() return self.parent end
function Frame:SetPoint() end
function Frame:ClearAllPoints() end
function Frame:SetFrameStrata() end
function Frame:SetMovable() end
function Frame:RegisterForDrag() end
function Frame:StartMoving() end
function Frame:StopMovingOrSizing() end
function Frame:EnableMouse(on) self.mouse = on end
function Frame:IsMouseEnabled() return self.mouse end
function Frame:SetClampedToScreen() end
function Frame:SetAlpha(a) self.alpha = a end
function Frame:GetAlpha() return self.alpha end
function Frame:SetScale(s) self.scale = s end
function Frame:GetScale() return self.scale end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:RegisterEvent(e) self.events[e] = true end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text end
function Frame:LockHighlight() self.highlighted = true end
function Frame:UnlockHighlight() self.highlighted = false end
function Frame:IsShown() return self.shown end
function Frame:Show()
  if self.shown then return end
  self.shown = true
  if self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Frame:Hide()
  if not self.shown then return end
  self.shown = false
  if self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Frame:CreateFontString() return newFrame("FontString") end
function Frame:Click() if self.scripts.OnClick then self.scripts.OnClick(self) end end

-- opts.template picks the shape of BasicFrameTemplateWithInset:
--   "forever" (default) like the Forever client: a named $parentCloseButton and an InsetBg texture
--   "modern" with CloseButton and Inset parent keys
--   "named" like "forever" but with the inset texture reachable only by its global name
--   "bare" with no close button or inset at all
function M.new(opts)
  local shape = (opts and opts.template) or "forever"
  local env = { frames = {}, closed = 0, UISpecialFrames = {}, timers = {} }
  env.UIParent = newFrame("Frame", "UIParent")
  env.C_Timer = { After = function(_, fn) env.timers[#env.timers + 1] = fn end }
  env.runTimers = function()
    local due = env.timers
    env.timers = {}
    for _, fn in ipairs(due) do fn() end
  end
  env.CreateFrame = function(kind, name, parent, template)
    local f = newFrame(kind, name, parent, template)
    if template == "BasicFrameTemplateWithInset" and shape ~= "bare" then
      local close = newFrame("Button", name and (name .. "CloseButton"), f)
      close:SetScript("OnClick", function() f:Hide() end)
      if shape == "modern" then
        f.CloseButton = close
        f.Inset = newFrame("Frame", nil, f)
      else
        if name then env[name .. "CloseButton"] = close end
        local bg = newFrame("Texture", name and (name .. "InsetBg"), f)
        if shape == "named" then
          if name then env[name .. "InsetBg"] = bg end
        else
          f.InsetBg = bg
        end
      end
    end
    env.frames[#env.frames + 1] = f
    if name then env[name] = f end
    return f
  end
  -- Like the client: closing fires AUCTION_HOUSE_CLOSED once, and the
  -- client hides Blizzard's window, whose OnHide closes the AH again (a no-op).
  env.open = false
  env.CloseAuctionHouse = function()
    env.closed = env.closed + 1
    if not env.open then return end
    env.open = false
    env.fire("AUCTION_HOUSE_CLOSED")
    env.AuctionFrame:Hide()
  end
  -- Blizzard's legacy window, shown by the client on AUCTION_HOUSE_SHOW.
  env.AuctionFrame = newFrame("Frame", "AuctionFrame", env.UIParent)
  env.AuctionFrame.shown = false
  env.AuctionFrame:SetScript("OnHide", function() env.CloseAuctionHouse() end)
  env.openAuctionHouse = function()
    env.open = true
    env.AuctionFrame:Show()
    env.fire("AUCTION_HOUSE_SHOW")
    env.runTimers()
  end
  -- Escape: the client hides UI panels first, then UISpecialFrames.
  env.pressEscape = function()
    env.AuctionFrame:Hide()
    for _, name in ipairs(env.UISpecialFrames) do env[name]:Hide() end
  end
  -- Fire an event at every frame registered for it.
  env.fire = function(event)
    for _, f in ipairs(env.frames) do
      if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event) end
    end
  end
  return env
end

return M
