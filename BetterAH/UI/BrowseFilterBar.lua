-- Browse's category and filters (#92): a Category button in the search row that opens a menu of
-- Forever's categories (up to three columns: category, subcategory, slot), and a row of filters under
-- it: Usable by me, Exact name, a Rarity button with its own menu, and Clear filters. Layout follows
-- artboard 6 of the Browse mockup linked from #90 (Christian picked the drop-down, 2026-11-26). The
-- rules live in Core/BrowseFilters.lua; the category tree comes from BrowseAPI:categories().
local _, ns = ...
ns = ns or {}

local Bar = {}
Bar.__index = Bar

Bar.ALL = "All items"
Bar.COLUMN = 132 -- one column of the category menu
Bar.ENTRY = 18
Bar.ENTRIES = 20 -- entries a column shows; a longer list is cut, with "and N more" on its last line
Bar.TOP = 24 -- room the filter row takes under the search row

function Bar.new(view)
  return setmetatable({ view = view, env = view.env, path = nil, chips = ns.BrowseFilters.defaults() }, Bar)
end

-- Where this character's category and filters are kept (BetterAHDB.browse.characters[key]), or nil.
function Bar:saved()
  local settings = self.view:settings()
  local key = self.view:characterKey()
  if not (settings and key) then return nil end
  if type(settings.characters) ~= "table" then settings.characters = {} end
  if type(settings.characters[key]) ~= "table" then settings.characters[key] = {} end
  return settings.characters[key]
end

-- Picks up this character's last category and filters.
function Bar:load()
  local saved = self:saved()
  if not saved then return end
  self.chips = ns.BrowseFilters.normalize(saved.chips)
  self.path = Bar.cleanPath(saved.path)
end

function Bar:save()
  local saved = self:saved()
  if not saved then return end
  saved.chips = ns.BrowseFilters.normalize(self.chips)
  saved.path = self.path
end

function Bar.cleanPath(path)
  if type(path) ~= "table" then return nil end
  local out = {}
  for _, name in ipairs(path) do
    if type(name) ~= "string" or name == "" then return nil end
    out[#out + 1] = name
  end
  return #out > 0 and out or nil
end

local function check(env, parent, label, tooltipTitle, tooltip, onClick)
  local c = env.CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(20, 20)
  local text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("LEFT", c, "RIGHT", 0, 1)
  text:SetText(label)
  c.label = text
  c:SetScript("OnClick", onClick)
  ns.Window.tooltip(env, c, tooltipTitle, tooltip)
  return c
end

local function menuFrame(env, parent, width, height)
  local m = env.CreateFrame("Frame", nil, parent)
  m:SetSize(width, height)
  m:SetFrameStrata("HIGH")
  m:EnableMouse(true)
  -- The wheel over a menu shouldn't scroll the results under it.
  m:EnableMouseWheel(true)
  m:SetScript("OnMouseWheel", function() end)
  local bg = m:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(m)
  bg:SetColorTexture(0.06, 0.05, 0.04, 0.97)
  local edges = { { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
    { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }
  for _, e in ipairs(edges) do
    local t = m:CreateTexture(nil, "BORDER")
    t:SetColorTexture(0.79, 0.64, 0.23, 1)
    t:SetPoint(e[1], m, e[1], 0, 0)
    t:SetPoint(e[2], m, e[2], 0, 0)
    if e[3] then t:SetHeight(1) else t:SetWidth(1) end
  end
  m:Hide()
  return m
end

-- The Category button right of anchor (the second level box), the filter row under the search row,
-- and their menus.
function Bar:build(panel, anchor)
  local env = self.env
  local button = env.CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  button:SetSize(120, 22)
  button:SetPoint("LEFT", anchor, "RIGHT", 12, 0)
  local label = button.GetFontString and button:GetFontString()
  if label then
    label:SetWidth(108) -- a long path ("Trade Goods / Elemental") is cut, not drawn past the button
    if label.SetWordWrap then label:SetWordWrap(false) end
  end
  button:SetScript("OnClick", function() self:toggleMenu("categories") end)
  ns.Window.tooltip(env, button, "Category",
    "Search one category of the auction house. Pick All items to search everything.")
  self.categoryButton = button

  local usable = check(env, panel, "Usable by me", "Usable by me",
    "Only items this character can use.", function(c) self:setChip("usable", c:GetChecked()) end)
  usable:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -24)
  self.usableCheck = usable
  local exact = check(env, panel, "Exact name", "Exact name",
    "Only items named exactly what you typed.", function(c) self:setChip("exact", c:GetChecked()) end)
  exact:SetPoint("LEFT", usable, "RIGHT", 82, 0)
  self.exactCheck = exact

  local rarity = env.CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  rarity:SetSize(140, 20)
  rarity:SetPoint("LEFT", exact, "RIGHT", 76, 0)
  rarity:SetScript("OnClick", function() self:toggleMenu("rarity") end)
  ns.Window.tooltip(env, rarity, "Rarity", "Which item qualities to search for.")
  self.rarityButton = rarity

  local clear = env.CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  clear:SetSize(90, 20)
  clear:SetPoint("LEFT", rarity, "RIGHT", 8, 0)
  clear:SetText("Clear filters")
  clear:SetScript("OnClick", function() self:clear() end)
  ns.Window.tooltip(env, clear, "Clear filters", "Back to all items, every rarity, and no other filters.")
  self.clearButton = clear

  -- The category menu: three columns of entries.
  local menu = menuFrame(env, panel, Bar.COLUMN * 3 + 8, Bar.ENTRIES * Bar.ENTRY + 8)
  menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
  self.categoryMenu = menu
  self.columns = {}
  for c = 1, 3 do
    local col = {}
    for i = 1, Bar.ENTRIES do
      local b = env.CreateFrame("Button", nil, menu)
      b:SetSize(Bar.COLUMN - 4, Bar.ENTRY)
      b:SetPoint("TOPLEFT", menu, "TOPLEFT", 4 + (c - 1) * Bar.COLUMN, -4 - (i - 1) * Bar.ENTRY)
      local hl = b:CreateTexture(nil, "HIGHLIGHT")
      hl:SetAtlas(ns.Window.ART.rowHighlight, false)
      hl:SetAllPoints(b)
      hl:SetBlendMode("ADD")
      local sel = b:CreateTexture(nil, "ARTWORK")
      sel:SetAtlas(ns.Window.ART.rowSelected, false)
      sel:SetAllPoints(b)
      sel:SetAlpha(0.5)
      sel:Hide()
      b.selectedTexture = sel
      local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      text:SetPoint("LEFT", b, "LEFT", 6, 0)
      text:SetWidth(Bar.COLUMN - 22)
      text:SetJustifyH("LEFT")
      if text.SetWordWrap then text:SetWordWrap(false) end
      b.text = text
      local more = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      more:SetPoint("RIGHT", b, "RIGHT", -4, 0)
      more:SetText(">")
      b.more = more
      local column, index = c, i
      b:SetScript("OnClick", function() self:pick(column, index) end)
      col[i] = b
    end
    self.columns[c] = col
  end

  -- The rarity menu: a check box per quality.
  local rm = menuFrame(env, panel, 140, #ns.BrowseFilters.RARITIES * 20 + 8)
  rm:SetPoint("TOPLEFT", rarity, "BOTTOMLEFT", 0, -2)
  self.rarityMenu = rm
  self.rarityChecks = {}
  for i, r in ipairs(ns.BrowseFilters.RARITIES) do
    local key = r.key
    local c = check(env, rm, r.label, r.label, "Include " .. r.label:lower() .. " items.",
      function(box) self:setRarity(key, box:GetChecked()) end)
    c:SetPoint("TOPLEFT", rm, "TOPLEFT", 6, -4 - (i - 1) * 20)
    c.quality = i - 1
    self.rarityChecks[i] = c
  end

  self:load()
  self:render()
end

-- The tree as the client has it now.
function Bar:tree()
  local api = self.view:api()
  return api and api.categories and api:categories() or {}
end

-- The chosen category from the tree, or nil (All items, or a category the client no longer has).
function Bar:category()
  if not self.path then return nil end
  return ns.BrowseFilters.find(self:tree(), self.path)
end

function Bar:label()
  if not self.path then return Bar.ALL end
  return ns.BrowseFilters.label(self.path)
end

function Bar:isOpen(which)
  local m = which == "rarity" and self.rarityMenu or self.categoryMenu
  return m ~= nil and m:IsShown()
end

function Bar:toggleMenu(which)
  local open = self:isOpen(which)
  self:closeMenus()
  if open then return end
  if which == "rarity" then
    self.rarityMenu:Show()
  else
    -- Open at the chosen category, so its columns show where it sits.
    self.browsing = self.path and { unpack(self.path) } or {}
    self.categoryMenu:Show()
  end
  self:render()
end

function Bar:closeMenus()
  if self.categoryMenu then self.categoryMenu:Hide() end
  if self.rarityMenu then self.rarityMenu:Hide() end
end

-- The entries of column c of the category menu: All items and the top categories, then the children
-- of what is open in the column before ("All <name>" first, for the whole of it).
function Bar:columnEntries(c)
  local tree = self:tree()
  if c == 1 then
    local out = { { label = Bar.ALL, path = nil } }
    for _, node in ipairs(tree) do out[#out + 1] = { label = node.name, path = { node.name }, node = node } end
    return out
  end
  local parentPath = {}
  for i = 1, c - 1 do
    if not (self.browsing and self.browsing[i]) then return {} end
    parentPath[i] = self.browsing[i]
  end
  local parent = ns.BrowseFilters.find(tree, parentPath)
  if not (parent and #parent.children > 0) then return {} end
  local out = { { label = "All " .. parent.name:lower(), path = parentPath, node = parent, whole = true } }
  for _, node in ipairs(parent.children) do
    local path = { unpack(parentPath) }
    path[#path + 1] = node.name
    out[#out + 1] = { label = node.name, path = path, node = node }
  end
  return out
end

local function samePath(a, b)
  if a == nil or b == nil then return a == b end
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

-- A click in the category menu: a category with subcategories opens them in the next column and is
-- chosen; anything else is chosen and the menu closes. Choosing searches straight away.
function Bar:pick(c, i)
  local e = self.shownEntries and self.shownEntries[c] and self.shownEntries[c][i]
  if not e then return end
  local opens = e.node and not e.whole and #e.node.children > 0 and c < 3
  self.browsing = e.path and { unpack(e.path) } or {}
  self.path = e.path and { unpack(e.path) } or nil
  self:save()
  if not opens then self:closeMenus() end
  self:render()
  self.view:filtersChanged(true, opens)
end

function Bar:setChip(key, on)
  self.chips[key] = on and true or false
  self:save()
  self:render()
  self.view:filtersChanged(false)
end

function Bar:setRarity(key, on)
  self.chips.rarity[key] = on and true or false
  self:save()
  self:render()
  self.view:filtersChanged(false)
end

-- Back to All items and the default filters. Leaving a category searches everything at once, as
-- picking All items would; filters alone wait for Search.
function Bar:clear()
  local hadCategory = self.path ~= nil
  self.path, self.chips = nil, ns.BrowseFilters.defaults()
  self:closeMenus()
  self:save()
  self:render()
  self.view:filtersChanged(hadCategory)
end

-- Sets the category and filters from a search in the history.
function Bar:restore(search)
  local category = search and search.category
  self.path = Bar.cleanPath(category and category.path)
  self.chips = ns.BrowseFilters.fromHistory(search and search.filters)
  self:closeMenus()
  self:save()
  self:render()
end

-- What a browse query needs: { category = node or nil, path, chips }. A saved category the client no
-- longer has is dropped (and nil returned as the second value says why).
function Bar:input()
  local node = self:category()
  if self.path and not node and #self:tree() > 0 then
    local gone = self:label()
    self.path = nil
    self:save()
    self:render()
    return { chips = self.chips },
      string.format("The category %s isn't on this auction house, so everything was searched.", gone)
  end
  return { category = node, path = node and self.path or nil, chips = self.chips }
end

-- What the search history keeps for these filters: category = { label, path } and filters.
function Bar:history()
  local category = self.path and { label = self:label(), path = { unpack(self.path) } } or nil
  return category, ns.BrowseFilters.historyFilters(self.chips)
end

function Bar:render()
  if not self.categoryButton then return end
  self.categoryButton:SetText(self:label())
  self.usableCheck:SetChecked(self.chips.usable)
  self.exactCheck:SetChecked(self.chips.exact)
  self.rarityButton:SetText(ns.BrowseFilters.rarityText(self.chips) or "Any rarity")
  self.clearButton:SetShown(self.path ~= nil or not ns.BrowseFilters.isDefault(self.chips))
  local api = self.view:api()
  for i, c in ipairs(self.rarityChecks) do
    c:SetChecked(self.chips.rarity[ns.BrowseFilters.RARITIES[i].key])
    if api then c.label:SetTextColor(api:qualityColor(c.quality)) end
  end
  if not self:isOpen("categories") then return end
  self.shownEntries = {}
  for c, col in ipairs(self.columns) do
    local entries = self:columnEntries(c)
    self.shownEntries[c] = entries
    local cut = #entries > #col
    for i, b in ipairs(col) do
      local e = entries[i]
      if cut and i == #col then
        e = { label = string.format("and %d more", #entries - #col + 1), more = true }
      end
      b:SetShown(e ~= nil)
      if b.EnableMouse then b:EnableMouse(e ~= nil and not e.more) end
      if e then
        b.text:SetText(e.label)
        b.more:SetShown(e.node ~= nil and not e.whole and #e.node.children > 0 and c < 3)
        local open = e.path and self.browsing and samePath(e.path, { unpack(self.browsing, 1, #e.path) })
        b.selectedTexture:SetShown((samePath(e.path, self.path)) or (open and not e.whole) or false)
      end
    end
  end
end

ns.BrowseFilterBar = Bar
return Bar
