-- A small line chart (#106): a value line and its trend line, drawn from a ValueHistory.layout. Lines
-- use the client's Frame:CreateLine; a client without it gets the same lines drawn as dots.
local _, ns = ...
ns = ns or {}

local ValueChart = {}
ValueChart.__index = ValueChart

ValueChart.VALUE_COLOR = { 1, 0.82, 0, 1 }
ValueChart.UP_COLOR = { 0.12, 1, 0, 0.85 }
ValueChart.DOWN_COLOR = { 1, 0.29, 0.23, 0.85 }
ValueChart.FLAT_COLOR = { 0.6, 0.6, 0.6, 0.85 }
local DOT_STEP = 3 -- px between dots when lines are drawn as dots

function ValueChart.new(env, parent, width, height)
  local f = env.CreateFrame("Frame", nil, parent)
  f:SetSize(width, height)
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(f)
  bg:SetColorTexture(0, 0, 0, 0.4)
  local self = setmetatable({ env = env, frame = f, width = width, height = height, pools = { line = {}, dot = {} },
    used = { line = 0, dot = 0 } }, ValueChart)
  self.high = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  self.high:SetPoint("TOPLEFT", f, "TOPLEFT", 3, -2)
  self.low = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  self.low:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 3, 2)
  self.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  self.empty:SetPoint("CENTER", f, "CENTER", 0, 0)
  self.empty:SetWidth(width - 16)
  return self
end

local function take(self, kind)
  local pool = self.pools[kind]
  self.used[kind] = self.used[kind] + 1
  local item = pool[self.used[kind]]
  if not item then
    if kind == "line" then
      item = self.frame:CreateLine(nil, "ARTWORK")
    else
      item = self.frame:CreateTexture(nil, "ARTWORK")
    end
    pool[self.used[kind]] = item
  end
  item:Show()
  return item
end

-- One straight piece from (x1, y1) to (x2, y2), in pixels from the chart's bottom left.
function ValueChart:segment(x1, y1, x2, y2, color, thickness)
  if self.frame.CreateLine then
    local line = take(self, "line")
    line:SetStartPoint("BOTTOMLEFT", self.frame, x1, y1)
    line:SetEndPoint("BOTTOMLEFT", self.frame, x2, y2)
    if line.SetThickness then line:SetThickness(thickness) end
    line:SetColorTexture(color[1], color[2], color[3], color[4])
    return
  end
  local length = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
  local steps = math.max(1, math.floor(length / DOT_STEP))
  for i = 0, steps do
    self:dot(x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps, color, thickness + 0.5)
  end
end

function ValueChart:dot(x, y, color, size)
  local d = take(self, "dot")
  d:SetSize(size, size)
  d:ClearAllPoints()
  d:SetPoint("CENTER", self.frame, "BOTTOMLEFT", x, y)
  d:SetColorTexture(color[1], color[2], color[3], color[4])
end

-- layout: from ValueHistory.layout (nil for no data); change: the trend's change, for its colour;
-- emptyText: what to say with no data.
function ValueChart:draw(layout, change, emptyText)
  self.used.line, self.used.dot = 0, 0
  local pad = 4
  local w, h = self.width - 2 * pad, self.height - 2 * pad
  local function at(p) return pad + p.x * w, pad + p.y * h end
  if layout then
    local points = layout.points
    for i = 2, #points do
      local x1, y1 = at(points[i - 1])
      local x2, y2 = at(points[i])
      self:segment(x1, y1, x2, y2, ValueChart.VALUE_COLOR, 1.5)
    end
    local lx, ly = at(points[#points])
    self:dot(lx, ly, ValueChart.VALUE_COLOR, 4)
    if layout.trend then
      local x1, y1 = at(layout.trend[1])
      local x2, y2 = at(layout.trend[2])
      local color = (change or 0) < 0 and ValueChart.DOWN_COLOR
        or (change or 0) > 0 and ValueChart.UP_COLOR or ValueChart.FLAT_COLOR
      self:segment(x1, y1, x2, y2, color, 1)
    end
    self.high:SetText(ns.Money.short(layout.high))
    self.low:SetText(layout.low ~= layout.high and ns.Money.short(layout.low) or "")
    self.empty:SetText("")
  else
    self.high:SetText("")
    self.low:SetText("")
    self.empty:SetText(emptyText or "")
  end
  for kind, pool in pairs(self.pools) do
    for i = self.used[kind] + 1, #pool do pool[i]:Hide() end
  end
end

ns.ValueChart = ValueChart
return ValueChart
