-- The Disenchant view, in tabs. Values (issue #45): what one green of each item level band is worth
-- disenchanted on this market, after the auction house cut, worked out live from the materials' market
-- values; it replaces the spreadsheet step of disenchant sniping. Targets (#47): the greens to buy and
-- the most to pay for each. Snipe (#12) comes next. The rules live in Core/Disenchant.lua and
-- Core/Targets.lua; this file only draws them. Layout follows the mockup linked from #47.
local _, ns = ...
ns = ns or {}

local DisenchantView = {}
DisenchantView.__index = DisenchantView

DisenchantView.TABS = { { "values", "Values" }, { "targets", "Targets" }, { "snipe", "Snipe" } }
DisenchantView.TARGET_COLUMNS = {
  { "", 4, 18 }, { "Target", 26, 140, "LEFT" }, { "Item types", 168, 100, "LEFT" }, { "Worth", 270, 85 },
  { "Profit", 357, 80 }, { "Max price", 439, 97 },
}
local TAB_HEIGHT = 28 -- the tab row above each tab's own panel

DisenchantView.COLUMNS = {
  { "Item level", 4, 90 }, { "Required level", 100, 100, "LEFT" }, { "Armor", 205, 105 }, { "Weapon", 315, 105 },
  { "Oldest price", 425, 110 },
}

-- The view's settings, saved in BetterAHDB.disenchant. The Arcane Salvager is on unless turned off.
function DisenchantView.options(addon)
  local saved = addon and addon.disenchant
  return { salvager = not (saved and saved.salvager == false) }
end

-- "26-30", or "61+" for the open-ended top band (open: that band's item level max).
local function range(min, max, open)
  if (open or max) >= 99 then return min .. "+" end
  return min .. "-" .. max
end
DisenchantView.range = range

-- One row per green band: { band, armor = { value, net, breakdown, missing }, weapon = {...}, priced, mats,
-- oldest }. priceOf(materialID) gives a market value or nil; dayOf(materialID), if given, the last day a
-- scan or check saw the material, and oldest is the oldest of those among the priced materials. Pure,
-- so the numbers are tested without frames.
function DisenchantView.rows(priceOf, opts, dayOf)
  local out = {}
  for _, band in ipairs(ns.Disenchant.greenBands()) do
    local row = { band = band }
    local seen, mats, priced = {}, 0, 0
    for _, class in ipairs({ "armor", "weapon" }) do
      local value, breakdown, missing = ns.Disenchant.value({ quality = ns.Disenchant.UNCOMMON, class = class,
        level = band.min }, priceOf, opts)
      row[class] = { value = value, net = ns.Disenchant.net(value), breakdown = breakdown, missing = missing }
      for _, y in ipairs(breakdown or {}) do
        if not seen[y.id] then
          seen[y.id] = true
          mats = mats + 1
          if y.price then
            priced = priced + 1
            local day = dayOf and dayOf(y.id)
            if day and (not row.oldest or day < row.oldest) then row.oldest = day end
          end
        end
      end
    end
    row.priced, row.mats = priced, mats
    out[#out + 1] = row
  end
  return out
end

-- The "Prices from" cell: how many materials have a price, or how old the oldest price is.
function DisenchantView.ageText(row, today)
  if row.priced < row.mats then return string.format("%d of %d priced", row.priced, row.mats) end
  if not (row.oldest and today) then return "all priced" end
  local age = today - row.oldest
  if age <= 0 then return "today" end
  if age == 1 then return "yesterday" end
  return age .. " days ago"
end

-- A value cell: the value after the cut, marked * when some material had no price, or - with none.
function DisenchantView.cellText(class)
  if not class.net then return "-" end
  return ns.Money.format(class.net) .. ((class.missing or 0) > 0 and " *" or "")
end

DisenchantView.CLASSES = { { "armor", "Armor", "What armor gives" }, { "weapon", "Weapons", "What weapons give" } }
DisenchantView.MATERIAL_LINES = 4

-- A material's chance as the player reads it: "75%", "2.5%".
function DisenchantView.chanceText(chance)
  return (string.format("%.1f", chance * 100):gsub("%.0$", "")) .. "%"
end

-- The band detail for one class ({ value, net, breakdown, missing } from rows): the big after-cut value,
-- the value before the cut, and one line per material with its share of the value (0 to 1).
function DisenchantView.classDetail(class)
  local money = ns.Money.short
  local out = { value = class.net and money(class.net) or "-",
    before = class.value and (money(class.value) .. "\nbefore the cut") or "No prices\nyet", lines = {} }
  for _, y in ipairs(class.breakdown or {}) do
    out.lines[#out.lines + 1] = { name = (y.name:gsub(" Essence$", " Ess.")), fullName = y.name,
      chance = DisenchantView.chanceText(y.chance),
      count = y.min == y.max and tostring(y.min) or (y.min .. "-" .. y.max),
      adds = y.value and money(y.value) or "no price",
      share = (y.value and class.value and class.value > 0) and math.min(1, y.value / class.value) or 0 }
  end
  return out
end

-- What a target's items are worth after the cut, from its band's row: the lower of its classes' values
-- (armor and weapons differ), and whether a material price was missing.
function DisenchantView.targetWorth(target, row)
  if not row then return nil, false end
  local worth, missing
  for class in pairs(ns.Targets.classes(target)) do
    local v = row[class]
    if v.net and (not worth or v.net < worth) then worth = v.net end
    if (v.missing or 0) > 0 then missing = true end
  end
  return worth, missing == true
end

-- A target's name: its types and the band's usual required level, like "Armor, req. 21-25".
function DisenchantView.targetName(target, row)
  local band = row and row.band
  if not band then return ns.Targets.typesText(target) end
  return ns.Targets.typesText(target) .. ", req. " .. range(band.required.min, band.required.max, band.max)
end

function DisenchantView.new(window, addon)
  return setmetatable({ window = window, env = window.env, addon = addon, tab = "values" }, DisenchantView)
end

local function subPanel(env, parent, width, height)
  local p = env.CreateFrame("Frame", nil, parent)
  p:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -TAB_HEIGHT)
  p:SetSize(width, height - TAB_HEIGHT)
  return p
end

function DisenchantView:build(f, x, y, width, height)
  local env = self.env
  local panel = env.CreateFrame("Frame", nil, f)
  panel:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
  panel:SetSize(width, height)
  self.panel = panel

  self.tabButtons = {}
  for i, tab in ipairs(DisenchantView.TABS) do
    local b = ns.Window.entryButton(env, panel, 90)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", (i - 1) * 94, 0)
    b:SetText(tab[2])
    b:SetScript("OnClick", function() self:selectTab(tab[1]) end)
    self.tabButtons[tab[1]] = b
  end

  local salvager = env.CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  salvager:SetSize(24, 24)
  salvager:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -112, 2)
  salvager:SetScript("OnClick", function(b) self:setSalvager(b:GetChecked() and true or false) end)
  ns.Window.tooltip(env, salvager, "Arcane Salvager",
    "Count the Arcane Salvager's 50% chance of one extra dust or essence per disenchant.")
  -- The template's own label, so clicking the words toggles it too; a plain one if the template has none.
  local label = salvager.Text
  if not label then
    label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", salvager, "RIGHT", 2, 0)
  end
  label:SetText("Arcane Salvager")
  if salvager.SetHitRectInsets then salvager:SetHitRectInsets(0, -84, 0, 0) end
  self.salvagerButton, self.salvagerLabel = salvager, label

  self:buildValues(subPanel(env, panel, width, height), width)
  self:buildTargets(subPanel(env, panel, width, height), width)
  self.snipe = ns.SnipeView.new(self)
  self.snipePanel = subPanel(env, panel, width, height)
  self.snipe:build(self.snipePanel, width)
  self:buildEditors()
  return panel
end

function DisenchantView:buildValues(p, width)
  local env = self.env
  self.valuesPanel = p
  local mats = env.CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  mats:SetSize(120, 22)
  mats:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  mats:SetText("Scan materials")
  mats:SetScript("OnClick", function() self.window:scanMaterials() end)
  ns.Window.tooltip(env, mats, "Scan materials",
    "Look up the 24 disenchant materials only, so these values use fresh prices without a full scan.")
  self.materialsButton = mats

  local status = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("LEFT", mats, "RIGHT", 10, 0)
  status:SetPoint("RIGHT", p, "RIGHT", 0, 0)
  status:SetJustifyH("LEFT")
  if status.SetMaxLines then status:SetMaxLines(2) end -- clear of the column headers below
  self.status = status

  self.rows = self.window:buildRows(p, DisenchantView.COLUMNS, function(index) self:selectRow(index) end)

  local note = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -32 - (#ns.Disenchant.greenBands() + 1) * 18 - 8)
  note:SetWidth(width - 8)
  note:SetJustifyH("LEFT")
  note:SetText("What one green of each band is worth disenchanted, after the 5% auction house cut. "
    .. "Required level is usually 5 below item level. * Some of its materials have no price yet, so the "
    .. "value is too low. Scan materials to price them.")
  self.note = note
end

function DisenchantView:buildTargets(p, width)
  local env = self.env
  self.targetsPanel = p
  local new = env.CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  new:SetSize(100, 22)
  new:SetPoint("TOPLEFT", p, "TOPLEFT", 0, 0)
  new:SetText("New target")
  new:SetScript("OnClick", function() self:newTarget(self.selected or 26) end)
  ns.Window.tooltip(env, new, "New target", "Add a target for green armor, in the band selected on Values "
    .. "(item level 26-30 if none). Change its item types, band and profit on the right.")
  self.newButton = new
  local hint = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("LEFT", new, "RIGHT", 10, 0)
  hint:SetPoint("RIGHT", p, "RIGHT", 0, 0)
  hint:SetJustifyH("LEFT")
  if hint.SetMaxLines then hint:SetMaxLines(2) end
  hint:SetText("Greens to buy for disenchanting. A target's max price is what its band is worth after the "
    .. "cut, minus your profit.")
  self.targetsHint = hint

  self.targetOffset = 0
  self.targetRows = self.window:buildRows(p, DisenchantView.TARGET_COLUMNS,
    function(index) self:selectTarget(index + self.targetOffset) end,
    function(offset) self.targetOffset = offset; self:render() end)
  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function(_, delta) self.targetOffset = self.targetOffset - delta * 3; self:render() end)
  for r, cells in ipairs(self.targetRows) do
    local box = env.CreateFrame("CheckButton", nil, cells.button, "UICheckButtonTemplate")
    box:SetSize(18, 18)
    box:SetPoint("LEFT", cells.button, "LEFT", 2, 0)
    box:SetScript("OnClick", function(b) self:setEnabled(r + self.targetOffset, b:GetChecked()) end)
    ns.Window.tooltip(env, box, "Snipe this target", "Untick to keep the target without sniping it.")
    cells.check = box
  end
  local start = env.CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  start:SetSize(width, 26)
  start:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
  start:SetScript("OnClick", function()
    self:selectTab("snipe")
    if not self.snipe.running then self.snipe:start() end
  end)
  self.startButton = start
  self.targetsEmpty = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  self.targetsEmpty:SetPoint("TOPLEFT", p, "TOPLEFT", 4, -56)
  self.targetsEmpty:SetWidth(width - 8)
  self.targetsEmpty:SetJustifyH("LEFT")
  self.targetsEmpty:SetText("No targets yet. Press New target, or pick a band on Values and make one from it.")
end

-- The Values tab's band detail (#52): both classes' after-cut values side by side, and the chosen
-- class's materials as a table with a bar for each one's share of the value.
function DisenchantView:buildBandDetail()
  local env, w = self.env, self.window
  local box = env.CreateFrame("Frame", nil, w.detailLayer)
  box:SetPoint("TOPLEFT", w.detailLayer, "TOPLEFT", 12, -30)
  box:SetSize(196, 330)
  box:Hide()
  self.bandDetail = box
  local function text(parent, font, x, y, width, justify)
    local t = parent:CreateFontString(nil, "OVERLAY", font)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    t:SetWidth(width)
    t:SetJustifyH(justify or "LEFT")
    if t.SetWordWrap then t:SetWordWrap(false) end
    return t
  end
  self.bandRequired = text(box, "GameFontDisableSmall", 0, 0, 196)
  self.classBoxes = {}
  for i, c in ipairs(DisenchantView.CLASSES) do
    local b = env.CreateFrame("Button", nil, box)
    b:SetPoint("TOPLEFT", box, "TOPLEFT", (i - 1) * 101, -18)
    b:SetSize(95, 66)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    b.bg = bg
    local hover = b:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(b)
    hover:SetColorTexture(1, 1, 1, 0.08)
    b.label = text(b, "GameFontNormalSmall", 6, -6, 85)
    b.label:SetText(c[2])
    b.value = text(b, "GameFontHighlightLarge", 6, -20, 85)
    b.before = text(b, "GameFontDisableSmall", 6, -38, 85)
    b.before:SetWordWrap(true)
    b:SetScript("OnClick", function() self.detailClass = c[1]; self:render() end)
    ns.Window.tooltip(env, b, c[2], "What one green of this band is worth disenchanted, after the 5% auction "
      .. "house cut. Click to see its materials.")
    self.classBoxes[c[1]] = b
  end
  local top = -114 -- the table's header
  self.materialsTitle = text(box, "GameFontNormalSmall", 0, top + 18, 196)
  local cols = { { "Material", 0, 98, "LEFT" }, { "Chance", 98, 30, "RIGHT" }, { "Count", 128, 24, "RIGHT" },
    { "Adds", 152, 44, "RIGHT" } }
  for _, col in ipairs(cols) do text(box, "GameFontDisableSmall", col[2], top, col[3], col[4]):SetText(col[1]) end
  self.materialLines = {}
  for i = 1, DisenchantView.MATERIAL_LINES do
    local y = top - i * 24
    local line = {}
    for c, col in ipairs(cols) do line[c] = text(box, "GameFontHighlightSmall", col[2], y, col[3], col[4]) end
    local track = box:CreateTexture(nil, "ARTWORK")
    track:SetColorTexture(0, 0, 0, 0.5)
    track:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y - 14)
    track:SetSize(196, 3)
    local fill = box:CreateTexture(nil, "OVERLAY")
    fill:SetColorTexture(0.79, 0.64, 0.23, 1)
    fill:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 0)
    fill:SetSize(1, 3)
    line.track, line.fill = track, fill
    self.materialLines[i] = line
  end
  self.materialsNote = text(box, "GameFontDisableSmall", 0, top - (DisenchantView.MATERIAL_LINES + 1) * 24 + 6, 196)
  if self.materialsNote.SetWordWrap then self.materialsNote:SetWordWrap(true) end
  self.salvagerNote = w.detailLayer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  self.salvagerNote:SetPoint("BOTTOMLEFT", w.detailLayer, "BOTTOMLEFT", 12, 42)
  self.salvagerNote:SetWidth(196)
  self.salvagerNote:SetJustifyH("LEFT")
  self.salvagerNote:Hide()
end

-- Fills the band detail for a row and the chosen class.
function DisenchantView:renderBandDetail(row, opts)
  local band = row.band
  self.bandRequired:SetText("Usually required level " .. range(band.required.min, band.required.max, band.max))
  local chosen = self.detailClass or "armor"
  for _, c in ipairs(DisenchantView.CLASSES) do
    local b, d = self.classBoxes[c[1]], DisenchantView.classDetail(row[c[1]])
    b.value:SetText(d.value .. (((row[c[1]].missing or 0) > 0 and row[c[1]].net) and "*" or ""))
    b.before:SetText(d.before)
    if c[1] == chosen then b.bg:SetColorTexture(0.79, 0.64, 0.23, 0.3) else b.bg:SetColorTexture(0, 0, 0, 0.35) end
    b.selected = c[1] == chosen
    if c[1] == chosen then
      self.materialsTitle:SetText(c[3])
      for i, line in ipairs(self.materialLines) do
        local m = d.lines[i]
        line[1]:SetText(m and m.name or "")
        line[2]:SetText(m and m.chance or "")
        line[3]:SetText(m and m.count or "")
        line[4]:SetText(m and m.adds or "")
        line.track:SetShown(m ~= nil)
        line.fill:SetShown(m ~= nil and m.share > 0)
        line.fill:SetWidth(math.max(1, math.floor(196 * (m and m.share or 0) + 0.5)))
        line.name = m and m.fullName
        line.share = m and m.share or 0
      end
      self.materialsNote:SetText((row[c[1]].missing or 0) > 0
        and "* A material has no price yet and counts as nothing. Scan materials to price it." or "")
    end
  end
  self.salvagerNote:SetText(opts.salvager and "Counts the Arcane Salvager's 50% chance of one extra dust or essence."
    or "Without an Arcane Salvager.")
  self.bandDetail:Show()
  self.salvagerNote:Show()
end

-- Controls on the detail panel: the Values tab's "make a target" button and the target editor.
function DisenchantView:buildEditors()
  local env, w = self.env, self.window
  local make = env.CreateFrame("Button", nil, w.detailLayer, "UIPanelButtonTemplate")
  make:SetSize(196, 22)
  make:SetPoint("BOTTOMLEFT", w.detailLayer, "BOTTOMLEFT", 12, 12)
  make:SetText("Make a target")
  ns.Window.tooltip(env, make, "Make a target", "Add a target for the greens shown above (armor or weapons) "
    .. "in this band, then change it on Targets.")
  make:SetScript("OnClick", function()
    if self.selected then self:newTarget(self.selected, self.detailClass) end
  end)
  make:Hide()
  self.makeButton = make
  self:buildBandDetail()

  local box = env.CreateFrame("Frame", nil, w.detailLayer)
  -- Under the title, which can take two lines.
  box:SetPoint("TOPLEFT", w.detailTitle, "BOTTOMLEFT", 0, -8)
  box:SetSize(196, 350)
  box:Hide()
  self.editor = box
  local function label(text, y)
    local l = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l:SetPoint("TOPLEFT", box, "TOPLEFT", 0, y)
    l:SetText(text)
    return l
  end
  local function button(text, width, y, x, onClick)
    local b = env.CreateFrame("Button", nil, box, "UIPanelButtonTemplate")
    b:SetSize(width, 20)
    b:SetPoint("TOPLEFT", box, "TOPLEFT", x, y)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
  end

  label("Item types", 0)
  self.typeBoxes = {}
  for i, t in ipairs(ns.Targets.TYPES) do
    local c = env.CreateFrame("CheckButton", nil, box, "UICheckButtonTemplate")
    c:SetSize(20, 20)
    c:SetPoint("TOPLEFT", box, "TOPLEFT", ((i - 1) % 2) * 98, -14 - math.floor((i - 1) / 2) * 20)
    local text = c.Text
    if not text then
      text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      text:SetPoint("LEFT", c, "RIGHT", 1, 0)
    end
    text:SetText(t.label)
    if c.SetHitRectInsets then c:SetHitRectInsets(0, -70, 0, 0) end
    c:SetScript("OnClick", function(b) self:setType(t.id, b:GetChecked()) end)
    self.typeBoxes[t.id] = c
  end

  label("Level band", -122)
  self.bandDown = button("<", 24, -138, 0, function() self:stepBand(-1) end)
  self.bandUp = button(">", 24, -138, 172, function() self:stepBand(1) end)
  self.bandText = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  self.bandText:SetPoint("TOPLEFT", box, "TOPLEFT", 28, -142)
  self.bandText:SetWidth(140)

  label("Profit you want", -168)
  local profit = env.CreateFrame("EditBox", nil, box, "InputBoxTemplate")
  profit:SetSize(70, 20)
  profit:SetPoint("TOPLEFT", box, "TOPLEFT", 6, -184)
  profit:SetAutoFocus(false)
  -- What is typed belongs to the target (and unit) that had the box when typing started, whatever is
  -- selected by the time focus goes. Escape drops it.
  profit:SetScript("OnEditFocusGained", function()
    local t = self:current()
    self.editing = t and { target = t, kind = t.profit and t.profit.kind or "percent" } or nil
  end)
  profit:SetScript("OnEscapePressed", function(e)
    self.editing = nil
    e:ClearFocus()
    self:render() -- back to the saved profit
  end)
  profit:SetScript("OnEnterPressed", function(e) e:ClearFocus() end)
  profit:SetScript("OnEditFocusLost", function(e)
    if type(env.EditBox_ClearHighlight) == "function" then pcall(env.EditBox_ClearHighlight, e) end
    self:saveProfit()
  end)
  self.profitInput = profit
  self.goldButton = button("Gold", 50, -184, 84, function() self:setProfitKind("gold") end)
  self.percentButton = button("%", 40, -184, 136, function() self:setProfitKind("percent") end)
  ns.Window.tooltip(env, self.percentButton, "Profit as a percent",
    "The share of what the item is worth disenchanted that you want to keep.")

  self.worthText = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  self.worthText:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -214)
  self.worthText:SetWidth(196)
  self.worthText:SetJustifyH("LEFT")
  label("Most it buys at", -240)
  self.maxText = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  self.maxText:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -256)
  self.editorStatus = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  self.editorStatus:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -276)
  self.editorStatus:SetWidth(196)
  self.editorStatus:SetJustifyH("LEFT")
  self.deleteButton = button("Delete target", 110, -326, 0, function() self:deleteTarget() end)
end

-- The saved targets.
function DisenchantView:targets()
  local addon = self.addon
  addon.disenchant = addon.disenchant or {}
  addon.disenchant.targets = addon.disenchant.targets or {}
  return ns.Targets.new(addon.disenchant.targets)
end

-- Ends typing in the profit box (saving it for its target) before the selection moves on.
function DisenchantView:dropFocus()
  local box = self.profitInput
  if box and box.HasFocus and box:HasFocus() then box:ClearFocus() end
end

function DisenchantView:hideEditors()
  self:dropFocus()
  if self.snipe then self.snipe:hide() end
  if self.editor then self.editor:Hide() end
  if self.makeButton then self.makeButton:Hide() end
  if self.bandDetail then self.bandDetail:Hide(); self.salvagerNote:Hide() end
end

function DisenchantView:selectTab(tab)
  self:dropFocus()
  self.tab = tab
  self.message = nil
  self:render()
end

function DisenchantView:setSalvager(on)
  local addon = self.addon
  addon.disenchant = addon.disenchant or {}
  addon.disenchant.salvager = on
  self:render()
end

function DisenchantView:selectRow(index)
  local row = self.list and self.list[index]
  if not row then return end
  self.selected = row.band.min
  self:render()
end

function DisenchantView:selectTarget(index)
  self:dropFocus()
  if not self:targets():list()[index] then return end
  self.target, self.message = index, nil
  self:render()
end

function DisenchantView:current()
  return self.target and self:targets():list()[self.target]
end

-- class: "weapon" for a target of the three weapon types, else the four armor types.
function DisenchantView:newTarget(band, class)
  self:dropFocus()
  local target, index = self:targets():add(band)
  if class == "weapon" then
    target.types = {}
    for _, t in ipairs(ns.Targets.TYPES) do if t.class == "weapon" then target.types[t.id] = true end end
  end
  self.tab, self.target, self.message = "targets", index, nil
  self:render()
end

function DisenchantView:deleteTarget()
  self:dropFocus()
  if not self:current() then return end
  self:targets():remove(self.target)
  self.target = nil
  self:render()
end

function DisenchantView:setEnabled(index, on)
  local t = self:targets():list()[index]
  if t then t.enabled = on and true or false end
  self:render()
end

function DisenchantView:setType(id, on)
  local t = self:current()
  if not t then return end
  t.types = t.types or {}
  t.types[id] = on and true or nil
  self.message = nil
  self:render()
end

-- Moves the target to the next or previous green band.
function DisenchantView:stepBand(by)
  local t = self:current()
  if not t then return end
  local bands = ns.Disenchant.greenBands()
  local found = false
  for i, band in ipairs(bands) do
    if band.min == t.band then
      local other = bands[i + by]
      if other then t.band = other.min end
      found = true
      break
    end
  end
  if not found then t.band = bands[1].min end -- a band no longer in the table: start again at the bottom
  self.message = nil
  self:render()
end

function DisenchantView:rowFor(band)
  for _, row in ipairs(self.list or {}) do
    if row.band.min == band then return row end
  end
  return nil
end

-- Switching between gold and percent keeps the max price where it was when the target has a worth
-- (a gold profit above the worth becomes 99%). Without a worth it starts from 10% or 2s.
function DisenchantView:setProfitKind(kind)
  local t = self:current()
  if not t or (t.profit and t.profit.kind == kind) then return end
  local worth = DisenchantView.targetWorth(t, self:rowFor(t.band))
  local profit = ns.Targets.profitOf(t, worth or 0)
  if kind == "percent" then
    t.profit = { kind = "percent", amount = worth and worth > 0 and math.min(99, math.floor(profit * 100 / worth
      + 0.5)) or 10 }
  else
    t.profit = { kind = "gold", amount = worth and profit or 200 }
  end
  self.message = nil
  self:render()
end

function DisenchantView:saveProfit()
  local editing = self.editing
  self.editing = nil
  if not editing then return end
  local t, kind = editing.target, editing.kind
  local still = false
  for _, other in ipairs(self:targets():list()) do still = still or other == t end
  if not still then return end
  local text = self.profitInput:GetText() or ""
  if text == (kind == "percent" and tostring(t.profit and t.profit.amount) or ns.Targets.profitText(t)) then
    return -- unchanged
  end
  local amount
  if kind == "percent" then
    amount = tonumber((text:gsub("%%", ""):gsub("%s", "")))
    if not (amount and amount >= 0 and amount < 100) then
      self.message = "Type a percent from 0 to 99, like 20."
      return self:render()
    end
  else
    amount = ns.Money.parse(text)
    if not amount then
      self.message = "Type an amount like 3s or 1g 5s."
      return self:render()
    end
  end
  t.profit = { kind = kind, amount = amount }
  self.message = nil
  self:render()
end

function DisenchantView:render()
  if not self.panel then return end
  local addon, w = self.addon, self.window
  local key = w:market()
  local now = addon.auctionAPI and addon.auctionAPI:now() or 0
  local opts = DisenchantView.options(addon)
  local prices = addon.prices
  local priceOf = function(id)
    return key and prices and (prices:marketValue(key, "i:" .. id, now))
  end
  local dayOf = function(id)
    local history = key and prices and prices:history(key, "i:" .. id) or {}
    return history[#history] and history[#history].day
  end
  self.list = DisenchantView.rows(priceOf, opts, dayOf)
  self.today = ns.MarketValue.day(now)
  self.salvagerButton:SetChecked(opts.salvager)
  for id, b in pairs(self.tabButtons) do ns.Window.markSelected(b, id == self.tab) end
  self.valuesPanel:SetShown(self.tab == "values")
  self.targetsPanel:SetShown(self.tab == "targets")
  self.snipePanel:SetShown(self.tab == "snipe")
  if self.tab ~= "snipe" then self.snipe:hide() end
  -- Only hidden when it goes away: hiding the editor would take focus from the profit box.
  if self.tab ~= "targets" then self.editor:Hide() end
  if self.tab ~= "values" then
    self.makeButton:Hide()
    self.bandDetail:Hide()
    self.salvagerNote:Hide()
  end
  if self.tab == "targets" then
    self:renderTargets()
  elseif self.tab == "snipe" then
    self.snipe:render()
  else
    self:renderValues(key, opts)
  end
end

function DisenchantView:renderValues(key, opts)
  local addon, w = self.addon, self.window
  local scanning = (addon.auctionAPI and addon.auctionAPI.pending) or w.materialScan
  if scanning then self.materialsButton:Disable() else self.materialsButton:Enable() end
  local text
  if w.materialStatus and w.materialMarket == key then
    text = w.materialStatus
  elseif key then
    text = "Prices from " .. ns.MarketKey.describe(key) .. "."
  else
    text = "Open the auction house to see prices."
  end
  self.status:SetText(text)

  local chosen
  for r, cells in ipairs(self.rows) do
    local row = self.list[r]
    if row then
      cells[1]:SetText(range(row.band.min, row.band.max))
      cells[2]:SetText(range(row.band.required.min, row.band.required.max, row.band.max))
      cells[3]:SetText(DisenchantView.cellText(row.armor))
      cells[4]:SetText(DisenchantView.cellText(row.weapon))
      cells[5]:SetText(DisenchantView.ageText(row, self.today))
      cells.button:Show()
      if row.band.min == self.selected then chosen = row end
    else
      for _, cell in ipairs(cells) do cell:SetText("") end
      cells.button:Hide()
    end
    cells.button.selectedTexture:SetShown(row ~= nil and row.band.min == self.selected)
  end
  if chosen then
    w.detailTitle:SetText(string.format("Greens of item level %s", range(chosen.band.min, chosen.band.max)))
    w.detailBody:SetText("")
    self:renderBandDetail(chosen, opts)
    self.makeButton:Show()
  else
    w.detailTitle:SetText("")
    w.detailBody:SetText("Select a band to see what each material adds.")
    self.bandDetail:Hide()
    self.salvagerNote:Hide()
  end
end

function DisenchantView:renderTargets()
  local w = self.window
  local list = self:targets():list()
  if self.target and not list[self.target] then self.target = nil end
  local money = ns.Money.format
  self.targetOffset = math.max(0, math.min(self.targetOffset, #list - #self.targetRows))
  ns.Window.syncScrollBar(self.targetRows.scrollBar, self.targetOffset, #list)
  for r, cells in ipairs(self.targetRows) do
    local index = r + self.targetOffset
    local t = list[index]
    if t then
      local row = self:rowFor(t.band)
      local worth, missing = DisenchantView.targetWorth(t, row)
      local max = ns.Targets.maxPrice(t, worth)
      cells[2]:SetText(DisenchantView.targetName(t, row))
      cells[3]:SetText(ns.Targets.typesText(t))
      cells[4]:SetText(worth and (money(worth) .. (missing and " *" or "")) or "-")
      cells[5]:SetText(ns.Targets.profitText(t))
      cells[6]:SetText(max and money(max) or "-")
      cells.check:SetChecked(t.enabled)
      cells.button:Show()
    else
      for _, cell in ipairs(cells) do cell:SetText("") end
      cells.button:Hide()
    end
    cells.button.selectedTexture:SetShown(t ~= nil and index == self.target)
  end
  self.targetsEmpty:SetShown(#list == 0)
  local ticked = #self.snipe:runnable()
  if self.snipe.running then
    self.startButton:SetText("Sniping: show it")
  else
    self.startButton:SetText(ticked > 0 and string.format("Start sniping %d target%s", ticked,
      ticked == 1 and "" or "s") or "Tick a target to snipe it")
  end
  if ticked > 0 or self.snipe.running then self.startButton:Enable() else self.startButton:Disable() end

  local t = self:current()
  if not t then
    self.editor:Hide()
    w.detailTitle:SetText("")
    w.detailBody:SetText(#list > 0 and "Select a target to change it." or "")
    return
  end
  local row = self:rowFor(t.band)
  w.detailTitle:SetText(DisenchantView.targetName(t, row))
  w.detailBody:SetText("")
  self.editor:Show()
  for id, c in pairs(self.typeBoxes) do c:SetChecked(t.types and t.types[id] == true) end
  self.bandText:SetText(row and string.format("Req. %s, item level %s",
    range(row.band.required.min, row.band.required.max, row.band.max), range(row.band.min, row.band.max)) or "-")
  local bands = ns.Disenchant.greenBands()
  if not row or row.band.min == bands[1].min then self.bandDown:Disable() else self.bandDown:Enable() end
  if row and row.band.min == bands[#bands].min then self.bandUp:Disable() else self.bandUp:Enable() end
  local percent = t.profit and t.profit.kind == "percent"
  if percent then
    self.percentButton:LockHighlight(); self.goldButton:UnlockHighlight()
  else
    self.goldButton:LockHighlight(); self.percentButton:UnlockHighlight()
  end
  -- Never rewrite the box while the player is typing in it.
  if not (self.profitInput.HasFocus and self.profitInput:HasFocus()) then
    self.profitInput:SetText(percent and tostring(t.profit.amount) or ns.Targets.profitText(t))
  end
  local worth, missing = DisenchantView.targetWorth(t, row)
  local max = ns.Targets.maxPrice(t, worth)
  self.worthText:SetText(worth and ("Worth " .. money(worth) .. " after the cut")
    or "No worth yet: scan materials on Values.")
  self.maxText:SetText(max and money(max) or "-")
  local note = self.message
  if not note and not next(ns.Targets.classes(t)) then note = "Pick at least one item type to snipe." end
  if not note and missing then note = "A material has no price yet, so this is too low. Scan materials on Values." end
  if not note and max == 0 then note = "The profit is more than the item is worth, so nothing would be bought." end
  self.editorStatus:SetText(note or "Updates as material prices change.")
end

ns.DisenchantView = DisenchantView
return DisenchantView
