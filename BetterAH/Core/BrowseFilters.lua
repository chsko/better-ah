-- Browse's categories and filters (#92), without the WoW API. Turns the client's category tree
-- (Blizzard's AuctionCategories, read by Game/BrowseAPI.lua) into plain data, finds a category by its
-- path of names, and turns the chosen category and filter chips into the parts of a browse query.
-- Specs in spec/browse_filters_spec.lua.
local _, ns = ...
ns = ns or {}

local BrowseFilters = {}

-- Enum.AuctionHouseFilter values (Forever's Blizzard_APIDocumentationGenerated/AuctionHouseEnums).
BrowseFilters.USABLE, BrowseFilters.EXACT = 2, 5
-- The rarity chips, Poor to Legendary, with their filter values.
BrowseFilters.RARITIES = {
  { key = "poor", label = "Poor", filter = 6 }, { key = "common", label = "Common", filter = 7 },
  { key = "uncommon", label = "Uncommon", filter = 8 }, { key = "rare", label = "Rare", filter = 9 },
  { key = "epic", label = "Epic", filter = 10 }, { key = "legendary", label = "Legendary", filter = 11 },
}
BrowseFilters.SEPARATOR = " / " -- between names in a category path, as shown

local function copyFilters(filters)
  local out = {}
  for _, f in ipairs(type(filters) == "table" and filters or {}) do
    if type(f) == "table" then
      out[#out + 1] = { classID = f.classID, subClassID = f.subClassID, inventoryType = f.inventoryType }
    end
  end
  return out
end

-- Plain categories from Blizzard's AuctionCategories: { name, filters, implicitFilter, children }, each
-- level in the client's order. Categories without a name, and the WoW Token (flagged WOW_TOKEN_FLAG),
-- are left out. depth limits how deep to go (default 3).
function BrowseFilters.tree(categories, depth)
  depth = depth or 3
  local out = {}
  if depth <= 0 or type(categories) ~= "table" then return out end
  for _, c in ipairs(categories) do
    local token = type(c) == "table" and type(c.flags) == "table" and c.flags.WOW_TOKEN_FLAG
    if type(c) == "table" and type(c.name) == "string" and c.name ~= "" and not token then
      out[#out + 1] = { name = c.name, filters = copyFilters(c.filters), implicitFilter = c.implicitFilter,
        children = BrowseFilters.tree(c.subCategories, depth - 1) }
    end
  end
  return out
end

-- The category at path (a list of names from the top), or nil when the client no longer has it.
function BrowseFilters.find(tree, path)
  if type(path) ~= "table" or #path == 0 then return nil end
  local level, found = tree, nil
  for _, name in ipairs(path) do
    found = nil
    for _, c in ipairs(level or {}) do
      if c.name == name then found = c break end
    end
    if not found then return nil end
    level = found.children
  end
  return found
end

-- "Armor / Mail" for a path; "" for none.
function BrowseFilters.label(path)
  if type(path) ~= "table" then return "" end
  return table.concat(path, BrowseFilters.SEPARATOR)
end

-- The chips as a player starts: every rarity on, usable and exact name off (Blizzard's defaults).
function BrowseFilters.defaults()
  local state = { usable = false, exact = false, rarity = {} }
  for _, r in ipairs(BrowseFilters.RARITIES) do state.rarity[r.key] = true end
  return state
end

-- A chip state from saved or hand-edited data, with anything missing at its default.
function BrowseFilters.normalize(state)
  local out = BrowseFilters.defaults()
  if type(state) ~= "table" then return out end
  out.usable = state.usable == true
  out.exact = state.exact == true
  if type(state.rarity) == "table" then
    for _, r in ipairs(BrowseFilters.RARITIES) do
      if state.rarity[r.key] ~= nil then out.rarity[r.key] = state.rarity[r.key] == true end
    end
  end
  return out
end

-- Whether the chips are as they start (the Clear filters link shows otherwise).
function BrowseFilters.isDefault(state)
  state = BrowseFilters.normalize(state)
  if state.usable or state.exact then return false end
  for _, r in ipairs(BrowseFilters.RARITIES) do
    if not state.rarity[r.key] then return false end
  end
  return true
end

-- The query's filters list (Enum.AuctionHouseFilter values) for a chip state, plus the chosen
-- category's implicit filter. With every rarity off nothing would match, so all rarities are sent then.
function BrowseFilters.filters(state, category)
  state = BrowseFilters.normalize(state)
  local out, any = {}, false
  if state.usable then out[#out + 1] = BrowseFilters.USABLE end
  if state.exact then out[#out + 1] = BrowseFilters.EXACT end
  for _, r in ipairs(BrowseFilters.RARITIES) do
    if state.rarity[r.key] then any = true end
  end
  for _, r in ipairs(BrowseFilters.RARITIES) do
    if state.rarity[r.key] or not any then out[#out + 1] = r.filter end
  end
  if category and category.implicitFilter then out[#out + 1] = category.implicitFilter end
  return out
end

-- The rarity chips that are on, as words: "Uncommon to Epic" for a run, "Poor, Rare" otherwise, nil
-- when all or none are on.
function BrowseFilters.rarityText(state)
  state = BrowseFilters.normalize(state)
  local on = {}
  for i, r in ipairs(BrowseFilters.RARITIES) do
    if state.rarity[r.key] then on[#on + 1] = i end
  end
  if #on == 0 or #on == #BrowseFilters.RARITIES then return nil end
  local run = on[#on] - on[1] + 1 == #on
  local R = BrowseFilters.RARITIES
  if #on == 1 then return R[on[1]].label end
  if run and on[#on] == #R then return R[on[1]].label .. " and up" end
  if run then return R[on[1]].label .. " to " .. R[on[#on]].label end
  local names = {}
  for i, n in ipairs(on) do names[i] = R[n].label end
  return table.concat(names, ", ")
end

-- The filters as the search history keeps them: a list of { key, label } in chip order (only what
-- differs from the defaults), so the same filters are the same search.
function BrowseFilters.historyFilters(state)
  state = BrowseFilters.normalize(state)
  local out = {}
  if state.usable then out[#out + 1] = { key = "usable", label = "usable by me" } end
  if state.exact then out[#out + 1] = { key = "exact", label = "exact name" } end
  local rarity = BrowseFilters.rarityText(state)
  if rarity then
    local keys = {}
    for _, r in ipairs(BrowseFilters.RARITIES) do
      if state.rarity[r.key] then keys[#keys + 1] = r.key end
    end
    out[#out + 1] = { key = "rarity:" .. table.concat(keys, "+"), label = rarity }
  end
  return out
end

-- Back from history's filter list to a chip state.
function BrowseFilters.fromHistory(filters)
  local state = BrowseFilters.defaults()
  for _, f in ipairs(type(filters) == "table" and filters or {}) do
    local key = type(f) == "table" and f.key or nil
    if key == "usable" then state.usable = true
    elseif key == "exact" then state.exact = true
    elseif type(key) == "string" and key:sub(1, 7) == "rarity:" then
      for _, r in ipairs(BrowseFilters.RARITIES) do state.rarity[r.key] = false end
      for k in key:sub(8):gmatch("[^+]+") do
        if state.rarity[k] ~= nil then state.rarity[k] = true end
      end
    end
  end
  return state
end

ns.BrowseFilters = BrowseFilters
return BrowseFilters
