-- Loading indicators (#67): Blizzard's gold spinner (SpinnerTemplate, as the auction house's own lists
-- use it) while we wait without knowing how long, and a gold progress bar where we can count.
-- Layout follows the mockup linked from #67.
local _, ns = ...
ns = ns or {}

local Loading = {}
Loading.__index = Loading

Loading.SPINNER = 16
Loading.BAR_WIDTH, Loading.BAR_HEIGHT = 120, 10
-- How long one sweep of a bar without a count takes, in seconds.
Loading.SWEEP = 1.4
Loading.BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

-- A spinner frame, hidden. Falls back to a plain frame on a client without SpinnerTemplate.
function Loading.spinner(env, parent, size)
  local ok, f = pcall(env.CreateFrame, "Frame", nil, parent, "SpinnerTemplate")
  if not (ok and f) then f = env.CreateFrame("Frame", nil, parent) end
  f:SetSize(size or Loading.SPINNER, size or Loading.SPINNER)
  f:Hide()
  return f
end

-- A gold progress bar on a dark ground, hidden. bar:SetMinMaxValues / SetValue as any status bar.
function Loading.bar(env, parent, width, height)
  local bar = env.CreateFrame("StatusBar", nil, parent)
  bar:SetSize(width or Loading.BAR_WIDTH, height or Loading.BAR_HEIGHT)
  bar:SetStatusBarTexture(Loading.BAR_TEXTURE)
  bar:SetStatusBarColor(1, 0.82, 0)
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(bar)
  bg:SetColorTexture(0, 0, 0, 0.6)
  bar.bg = bg
  bar:Hide()
  return bar
end

-- Puts a spinner and a bar in front of a status line. at = { point, rel, relPoint, x, y, width }: the
-- point the line's left edge is set with (text:SetPoint(point, rel, relPoint, x, y)), and its width
-- when it has a fixed one. Then :show(done, total) for a bar (total nil or 0: a bar that sweeps, for a
-- wait with no count yet), :spin() for a spinner after the text, :clear() for neither. The line moves
-- right of a bar (and narrows by as much, when it has a width).
function Loading.attach(env, parent, text, at)
  local self = setmetatable({ env = env, text = text, at = at }, Loading)
  local point = at[1] or "LEFT"
  self.point = point
  self.spinnerFrame = Loading.spinner(env, parent)
  self.spinnerFrame:SetPoint(point, at[2], at[3], at[4] or 0, at[5] or 0)
  self.barFrame = Loading.bar(env, parent)
  self.barFrame:SetPoint(point, at[2], at[3], at[4] or 0, at[5] or 0)
  self.barFrame:SetScript("OnUpdate", function(bar, elapsed) self:sweep(bar, elapsed) end)
  return self
end

-- The edge of a frame the line starts from: the same height as its own anchor point.
local RIGHT_OF = { LEFT = "RIGHT", TOPLEFT = "TOPRIGHT", BOTTOMLEFT = "BOTTOMRIGHT" }

function Loading:place(frame, width)
  local at = self.at
  if frame then
    self.text:SetPoint(self.point, frame, RIGHT_OF[self.point] or "RIGHT", 6, 0)
    if at[6] then self.text:SetWidth(at[6] - width - 6) end
  else
    self.text:SetPoint(self.point, at[2], at[3], at[4] or 0, at[5] or 0)
    if at[6] then self.text:SetWidth(at[6]) end
  end
end

function Loading:sweep(bar, elapsed)
  if not self.sweeping then return end
  self.t = ((self.t or 0) + (elapsed or 0)) % Loading.SWEEP
  bar:SetValue(self.t / Loading.SWEEP)
end

function Loading:show(done, total)
  self.spinnerFrame:Hide()
  local bar = self.barFrame
  if total and total > 0 then
    self.sweeping = false
    bar:SetMinMaxValues(0, total)
    bar:SetValue(math.max(0, math.min(done or 0, total)))
  else
    self.sweeping = true
    bar:SetMinMaxValues(0, 1)
  end
  bar:Show()
  self:place(bar, Loading.BAR_WIDTH)
end

-- The spinner goes after the line's text, so the text doesn't move each time it starts and stops.
-- Call it again after the text changes, to keep it at the end.
-- The line keeps room for it at its right end: a line with a fixed width narrows by as much, and a line
-- whose right edge is anchored must leave Loading.SPINNER + 6 px free there itself.
function Loading:spin()
  self.barFrame:Hide()
  self.sweeping = false
  self:place(nil)
  local text, at = self.text, self.at
  if at[6] then text:SetWidth(at[6] - Loading.SPINNER - 6) end
  local width = text.GetStringWidth and tonumber(text:GetStringWidth()) or 0
  local room = text.GetWidth and tonumber(text:GetWidth())
  if room and room > 0 then width = math.min(width, room) end
  local f = self.spinnerFrame
  f:ClearAllPoints()
  f:SetPoint("LEFT", text, "LEFT", width + 6, 0)
  f:Show()
end

function Loading:clear()
  self.barFrame:Hide()
  self.spinnerFrame:Hide()
  self.sweeping = false
  self:place(nil)
end

ns.Loading = Loading
return Loading
