-- Browse's category and filters (#92): a Category drop-down in the search row with Forever's categories
-- (up to three levels: category, subcategory, slot, each a submenu of the one before), and a row of
-- filters under it: Usable by me, Exact name, a Rarity drop-down of check boxes, and Clear filters. Both
-- drop-downs are Blizzard's own (UI/Dropdown.lua, #189). Layout follows
-- artboard 6 of the Browse mockup linked from #90 (Christian picked the drop-down, 2026-11-26). The
-- rules live in Core/BrowseFilters.lua; the category tree comes from BrowseAPI:categories().
local _, ns = ...
ns = ns or {}

local Bar = {}
Bar.__index = Bar

Bar.ALL = "All items"
Bar.LEVELS = 3 -- category, subcategory, slot
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

local function samePath(a, b)
  if a == nil or b == nil then return a == b end
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

-- Whether path is chosen, or holds the chosen category.
local function holds(path, chosen)
  if not chosen or #chosen < #path then return false end
  for i = 1, #path do if path[i] ~= chosen[i] then return false end end
  return true
end

-- The Category drop-down right of anchor (the second level box), the filter row under the search row.
function Bar:build(panel, anchor)
  local env = self.env
  local Dropdown = ns.Dropdown
  local category = Dropdown.create(env, panel, { width = 140, title = "Category",
    tip = "Search one category of the auction house. Pick All items to search everything.",
    text = function() return self:label() end,
    build = function(root) self:buildCategories(root) end })
  category:SetPoint("LEFT", anchor, "RIGHT", 12, 0)
  self.categoryButton = category

  local usable = check(env, panel, "Usable by me", "Usable by me",
    "Only items this character can use.", function(c) self:setChip("usable", c:GetChecked()) end)
  usable:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -24)
  self.usableCheck = usable
  local exact = check(env, panel, "Exact name", "Exact name",
    "Only items named exactly what you typed.", function(c) self:setChip("exact", c:GetChecked()) end)
  exact:SetPoint("LEFT", usable, "RIGHT", 82, 0)
  self.exactCheck = exact

  local rarity = Dropdown.create(env, panel, { width = 140, height = 20, title = "Rarity",
    tip = "Which item qualities to search for.",
    text = function() return ns.BrowseFilters.rarityText(self.chips) or "Any rarity" end,
    build = function(root) self:buildRarities(root) end })
  rarity:SetPoint("LEFT", exact, "RIGHT", 76, 0)
  self.rarityButton = rarity

  local clear = env.CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  clear:SetSize(90, 20)
  clear:SetPoint("LEFT", rarity, "RIGHT", 8, 0)
  clear:SetText("Clear filters")
  clear:SetScript("OnClick", function() self:clear() end)
  ns.Window.tooltip(env, clear, "Clear filters", "Back to all items, every rarity, and no other filters.")
  self.clearButton = clear

  self:load()
  self:render()
end

-- The category menu: All items, then each category; one with subcategories opens them in a submenu,
-- "All <name>" first for the whole of it.
function Bar:buildCategories(root)
  local tree = self:tree()
  ns.Dropdown.limit(root, #tree + 1)
  root:CreateRadio(Bar.ALL, function() return self.path == nil end, function() self:choose(nil) end)
  self:addCategories(root, tree, {}, 1)
end

function Bar:addCategories(description, nodes, parentPath, level)
  for _, node in ipairs(nodes) do
    local path = { unpack(parentPath) }
    path[#path + 1] = node.name
    local opens = #node.children > 0 and level < Bar.LEVELS
    local e = description:CreateRadio(node.name, function() return holds(path, self.path) end,
      function() self:choose(path, opens) end)
    if opens then
      ns.Dropdown.limit(e, #node.children + 1)
      e:CreateRadio("All " .. node.name:lower(), function() return samePath(path, self.path) end,
        function() self:choose(path) end)
      self:addCategories(e, node.children, path, level + 1)
    end
  end
end

-- The rarity menu: a check box per quality, in its colour. Ticking keeps the menu open.
function Bar:buildRarities(root)
  local api = self.view:api()
  for i, r in ipairs(ns.BrowseFilters.RARITIES) do
    local key, label = r.key, r.label
    if api then
      local red, green, blue = api:qualityColor(i - 1)
      if red then
        label = string.format("|cff%02x%02x%02x%s|r", math.floor(red * 255 + 0.5), math.floor(green * 255 + 0.5),
          math.floor(blue * 255 + 0.5), label)
      end
    end
    root:CreateCheckbox(label, function() return self.chips.rarity[key] == true end,
      function()
        ns.Dropdown.log("Rarity", r.label)
        self:setRarity(key, not self.chips.rarity[key])
      end)
  end
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

function Bar:closeMenus()
  if self.categoryButton then self.categoryButton:CloseMenu() end
  if self.rarityButton then self.rarityButton:CloseMenu() end
end

-- A category picked from the menu (nil: All items). Choosing searches straight away; opens: it has
-- subcategories to show, so the menu stays open.
function Bar:choose(path, opens)
  ns.Dropdown.log("Category", path and ns.BrowseFilters.label(path) or Bar.ALL)
  self.path = path and { unpack(path) } or nil
  self:save()
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
  self.categoryButton.refresh()
  self.usableCheck:SetChecked(self.chips.usable)
  self.exactCheck:SetChecked(self.chips.exact)
  self.rarityButton.refresh()
  self.clearButton:SetShown(self.path ~= nil or not ns.BrowseFilters.isDefault(self.chips))
end

ns.BrowseFilterBar = Bar
return Bar
