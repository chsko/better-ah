-- Browse's search history (#129): a panel right of the results, with pinned searches over recent ones.
-- A click on an entry searches again; the star pins it, the cross forgets it. The divider between the
-- results and this panel can be dragged to make it wider or narrower (BrowseView does the dragging).
-- Layout follows artboard 5 of the Browse mockup linked from #90. The rules live in
-- Core/SearchHistory.lua; this file only draws and wires.
local _, ns = ...
ns = ns or {}

local BrowseHistory = {}
BrowseHistory.__index = BrowseHistory

BrowseHistory.LINE = 28 -- one entry: its name over what else limited it
BrowseHistory.TOP = 26 -- room for the panel's title
BrowseHistory.FOOT = 58 -- room for the hint or a message (two lines) over the Clear recent button
BrowseHistory.TITLE = "Search history"
BrowseHistory.EMPTY = "Searches you run show up here, ready to run again."
BrowseHistory.HINT = "Click a search to run it again."
BrowseHistory.ART = { pinned = "auctionhouse-icon-favorite", unpinned = "auctionhouse-icon-favorite-off",
  remove = "common-icon-redx" }

-- view is the BrowseView: it runs the searches.
function BrowseHistory.new(view)
  return setmetatable({ view = view, env = view.env, offset = 0 }, BrowseHistory)
end

function BrowseHistory:history()
  return self.view.addon.searchHistory
end

-- The panel, as a child of parent, height high; BrowseHistory:layout places and sizes it.
function BrowseHistory:build(parent, height)
  local env = self.env
  local panel = env.CreateFrame("Frame", nil, parent)
  panel:SetHeight(height)
  panel:EnableMouseWheel(true)
  panel:SetScript("OnMouseWheel", function(_, delta) self:scroll(-delta * 2) end)
  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(panel)
  bg:SetColorTexture(0, 0, 0, 0.35)
  self.panel = panel

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -6)
  title:SetJustifyH("LEFT")
  title:SetText(BrowseHistory.TITLE)
  self.title = title

  self.lines = {}
  local count = math.max(1, math.floor((height - BrowseHistory.TOP - BrowseHistory.FOOT) / BrowseHistory.LINE))
  for i = 1, count do self.lines[i] = self:buildLine(panel, i) end

  local empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  empty:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -BrowseHistory.TOP - 6)
  empty:SetJustifyH("LEFT")
  empty:SetText(BrowseHistory.EMPTY)
  self.empty = empty

  local foot = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  -- Over the Clear recent button, full width and wrapping, so a refusal can be read at any width.
  foot:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 30)
  foot:SetJustifyH("LEFT")
  if foot.SetWordWrap then foot:SetWordWrap(true) end
  self.foot = foot
  local clear = env.CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  clear:SetSize(90, 20)
  clear:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 5)
  clear:SetText("Clear recent")
  clear:SetScript("OnClick", function() self:clearRecent() end)
  ns.Window.tooltip(env, clear, "Clear recent", "Forget every search that isn't pinned.")
  self.clearButton = clear
  return panel
end

-- One line of the list: a section heading, or an entry with its pin star, name, details, age and cross.
function BrowseHistory:buildLine(panel, i)
  local env = self.env
  local b = env.CreateFrame("Button", nil, panel)
  b:SetHeight(BrowseHistory.LINE)
  b:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -BrowseHistory.TOP - (i - 1) * BrowseHistory.LINE)
  local highlight = b:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAtlas(ns.Window.ART.rowHighlight, false)
  highlight:SetAllPoints(b)
  highlight:SetBlendMode("ADD")
  b.highlight = highlight
  b:SetScript("OnClick", function() self:choose(i) end)

  local heading = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  heading:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 8, 4)
  b.heading = heading

  local star = env.CreateFrame("Button", nil, b)
  star:SetSize(16, 16)
  star:SetPoint("LEFT", b, "LEFT", 6, 0)
  local starArt = star:CreateTexture(nil, "ARTWORK")
  starArt:SetAllPoints(star)
  star.art = starArt
  star:SetScript("OnClick", function() self:togglePin(i) end)
  b.star = star

  local name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  name:SetPoint("TOPLEFT", b, "TOPLEFT", 28, -3)
  name:SetJustifyH("LEFT")
  if name.SetWordWrap then name:SetWordWrap(false) end
  b.name = name
  local detail = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  detail:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
  detail:SetJustifyH("LEFT")
  if detail.SetWordWrap then detail:SetWordWrap(false) end
  b.detail = detail
  local age = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  age:SetPoint("TOPRIGHT", b, "TOPRIGHT", -26, -4)
  age:SetJustifyH("RIGHT")
  b.age = age

  local remove = env.CreateFrame("Button", nil, b)
  remove:SetSize(14, 14)
  remove:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  local removeArt = remove:CreateTexture(nil, "ARTWORK")
  removeArt:SetAtlas(BrowseHistory.ART.remove, false)
  removeArt:SetAllPoints(remove)
  removeArt:SetAlpha(0.7)
  remove:SetScript("OnClick", function() self:remove(i) end)
  ns.Window.tooltip(env, remove, "Remove", "Forget this search.")
  b.remove = remove
  return b
end

-- Places the panel at x in its parent, width wide, and fits its text to the width.
function BrowseHistory:layout(x, width)
  local panel = self.panel
  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT", panel:GetParent(), "TOPLEFT", x, 0)
  panel:SetWidth(width)
  self.width = width
  for _, line in ipairs(self.lines) do
    line:SetWidth(width)
    line.name:SetWidth(math.max(20, width - 28 - 60))
    line.detail:SetWidth(math.max(20, width - 28 - 26))
  end
  self.empty:SetWidth(width - 16)
  self.foot:SetWidth(width - 16)
end

function BrowseHistory:show(on)
  if self.panel then self.panel:SetShown(on) end
  if on then self:render() end
end

-- The list as lines: a heading over pinned searches, a heading over recent ones.
function BrowseHistory:entries()
  local history = self:history()
  local out = {}
  if not history then return out end
  local pinned, recent = history:list()
  if #pinned > 0 then
    out[#out + 1] = { heading = "PINNED" }
    for _, e in ipairs(pinned) do out[#out + 1] = e end
  end
  if #recent > 0 then
    out[#out + 1] = { heading = "RECENT" }
    for _, e in ipairs(recent) do out[#out + 1] = e end
  end
  return out
end

function BrowseHistory:scroll(by)
  self.offset = self.offset + by
  self:render()
end

function BrowseHistory:entryAt(i)
  local e = self.shown and self.shown[i]
  if e and not e.heading then return e end
  return nil
end

function BrowseHistory:choose(i)
  local e = self:entryAt(i)
  if not e then return end
  -- One search at a time, like the disabled Search button: the search row keeps what is searching.
  if self.view.searching then
    self.message = "Wait for this search to finish."
    return self:render()
  end
  self.message = nil
  self.view:searchAgain(e.search)
  self:render()
end

local function hideTooltip(env)
  if env.GameTooltip then env.GameTooltip:Hide() end
end

function BrowseHistory:togglePin(i)
  local e, history = self:entryAt(i), self:history()
  if not (e and history) then return end
  hideTooltip(self.env) -- it would still say Pin or Unpin
  local ok, why = history:pin(e.key, not e.pinned)
  self.message = not ok and why or nil
  self:render()
end

function BrowseHistory:remove(i)
  local e, history = self:entryAt(i), self:history()
  if not (e and history) then return end
  hideTooltip(self.env)
  history:remove(e.key)
  self.message = nil
  self:render()
end

function BrowseHistory:clearRecent()
  local history = self:history()
  if history then history:clearRecent() end
  self.offset, self.message = 0, nil
  self:render()
end

-- How long ago, short enough for the list: "now", "12 min", "3 h", "2 days".
function BrowseHistory.age(at, now)
  if not (at and at > 0 and now) then return "" end
  local d = math.max(0, now - at)
  if d < 60 then return "now" end
  if d < 3600 then return math.floor(d / 60) .. " min" end
  if d < 86400 then return math.floor(d / 3600) .. " h" end
  local days = math.floor(d / 86400)
  return days == 1 and "1 day" or (days .. " days")
end

function BrowseHistory:render()
  if not (self.panel and self.panel:IsShown()) then return end
  local all = self:entries()
  local count = #self.lines
  self.offset = math.max(0, math.min(self.offset, math.max(0, #all - count)))
  self.shown = {}
  local now = self.view:now()
  local recent = 0
  for _, e in ipairs(all) do
    if not e.heading and not e.pinned then recent = recent + 1 end
  end
  for i, line in ipairs(self.lines) do
    local e = all[i + self.offset]
    self.shown[i] = e
    line:SetShown(e ~= nil)
    if e then
      local heading = e.heading ~= nil
      line.heading:SetShown(heading)
      line.heading:SetText(e.heading or "")
      line.highlight:SetShown(not heading)
      if line.EnableMouse then line:EnableMouse(not heading) end
      line.star:SetShown(not heading)
      line.remove:SetShown(not heading)
      line.name:SetText(heading and "" or e.name)
      line.detail:SetText(heading and "" or e.detail)
      line.age:SetText((heading or e.pinned) and "" or BrowseHistory.age(e.at, now))
      if not heading then
        line.star.art:SetAtlas(e.pinned and BrowseHistory.ART.pinned or BrowseHistory.ART.unpinned, false)
        ns.Window.tooltip(self.env, line.star, e.pinned and "Unpin" or "Pin",
          e.pinned and "Let this search drop off the list like any other."
            or "Keep this search at the top of the list.")
      end
    end
  end
  self.empty:SetShown(#all == 0)
  self.clearButton:SetShown(recent > 0)
  self.foot:SetText(self.message or BrowseHistory.HINT)
  if self.message then self.foot:SetTextColor(1, 0.5, 0.25) else self.foot:SetTextColor(0.62, 0.62, 0.62) end
end

ns.BrowseHistory = BrowseHistory
return BrowseHistory
