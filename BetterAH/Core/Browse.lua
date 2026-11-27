-- Browse (#91): the rules behind the Browse view, without the WoW API. Turns what the player typed into
-- a browse query, browse results into table rows, and sorts the rows. Specs in spec/browse_spec.lua.
local _, ns = ...
ns = ns or {}

local Browse = {}

-- Cheapest first (Enum.AuctionHouseSortOrder.Price), so a search cut off at the page limit still shows
-- the cheapest items. The view sorts the rows again by whatever column the player picks.
Browse.PRICE_SORT = { { sortOrder = 0, reverseSort = false } }

-- The highest level a level box takes; Forever's cap is 60, but the client's own boxes allow more.
Browse.MAX_LEVEL = 999

-- How cheap or dear a lowest buyout is against the market value, in percent, for its colour.
Browse.CHEAP, Browse.DEAR = 85, 110

-- The columns rows can be sorted by, and which way each starts. Name sorts A to Z first, numbers low to high.
Browse.SORTS = { name = true, level = true, listed = true, lowest = true, value = true, percent = true }
Browse.DEFAULT_SORT = "lowest"

local function trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The name to search for: an item link becomes its name, anything else is the text as typed, trimmed.
function Browse.searchText(text)
  text = trim(text)
  local name = text:match("|h%[(.-)%]|h")
  if name then return name end
  return text
end

local function level(text)
  text = trim(text)
  if text == "" then return nil end
  local n = tonumber(text)
  if not n or n < 0 or n ~= math.floor(n) or n > Browse.MAX_LEVEL then return false end
  return n
end

-- A browse query from the search row: input = { text, minLevel, maxLevel } as typed (strings or
-- numbers). Returns the query for C_AuctionHouse.SendBrowseQuery, or nil and why. Levels are required
-- levels, as Forever's own auction house uses. A blank level box means no limit; boxes typed the wrong
-- way round are swapped.
function Browse.query(input)
  input = input or {}
  local lo, hi = level(input.minLevel), level(input.maxLevel)
  if lo == false or hi == false then
    return nil, string.format("Levels are whole numbers from 0 to %d.", Browse.MAX_LEVEL)
  end
  if lo and hi and lo > hi then lo, hi = hi, lo end
  local query = { searchString = Browse.searchText(input.text), minLevel = lo or 0, maxLevel = hi or 0,
    filters = {}, itemClassFilters = {}, sorts = Browse.PRICE_SORT }
  -- Categories and filter chips (#92): input.category is a category from BrowseFilters.tree (its item
  -- class filters, and its implicit filter), input.chips the chip state, input.path the category's names.
  local F = ns.BrowseFilters
  local category = type(input.category) == "table" and input.category or nil
  if category then
    for i, f in ipairs(category.filters or {}) do
      query.itemClassFilters[i] = { classID = f.classID, subClassID = f.subClassID, inventoryType = f.inventoryType }
    end
  end
  if F and (input.chips or category) then query.filters = F.filters(input.chips, category) end
  if type(input.path) == "table" and #input.path > 0 then query.path = input.path end
  return query
end

-- The search history panel beside the results (#129): how wide it starts, and how far the divider
-- between the two can be dragged. The results get the rest of Browse's width.
-- (At most 280, so the filter row, Category to Exact name, keeps room on the results side: #213.)
Browse.HISTORY_WIDTH, Browse.HISTORY_MIN, Browse.HISTORY_MAX = 260, 160, 280

-- A history panel width to use: a saved or dragged width rounded and kept in range, else the default.
function Browse.historyWidth(width)
  width = tonumber(width)
  if not width or width ~= width then return Browse.HISTORY_WIDTH end
  width = math.floor(width + 0.5)
  return math.max(Browse.HISTORY_MIN, math.min(Browse.HISTORY_MAX, width))
end

-- The results table's columns for a table width (the room the rows get): { header, x, width, justify,
-- sort column }. The number columns keep their widths at the right; the item name takes what is left.
Browse.NUMBER_COLUMNS = {
  { "Req.", 36, "level" }, { "Listed", 46, "listed" }, { "Lowest buyout", 92, "lowest" },
  { "Market value", 92, "value" }, { "Of market", 62, "percent" },
}
Browse.COLUMN_GAP = 6
function Browse.columns(width)
  local gap, numbers = Browse.COLUMN_GAP, 0
  for _, c in ipairs(Browse.NUMBER_COLUMNS) do numbers = numbers + c[2] + gap end
  local x = 4
  local name = math.max(60, width - x - numbers - 4)
  local cols = { { "Item", x, name, "LEFT", "name" } }
  x = x + name + gap
  for _, c in ipairs(Browse.NUMBER_COLUMNS) do
    cols[#cols + 1] = { c[1], x, c[2], nil, c[3] }
    x = x + c[2] + gap
  end
  return cols
end

-- The percentage of the market value a price is, rounded; nil without both.
function Browse.percent(price, value)
  if not (price and price > 0 and value and value > 0) then return nil end
  return math.floor(price * 100 / value + 0.5)
end

-- "cheap", "dear" or nil (in line with the market) for a percent from Browse.percent.
function Browse.tone(percent)
  if not percent then return nil end
  if percent <= Browse.CHEAP then return "cheap" end
  if percent >= Browse.DEAR then return "dear" end
  return nil
end

-- The same item key (item, item level, suffix): a row's identity across rebuilds.
function Browse.sameKey(a, b)
  return a ~= nil and b ~= nil and a.itemID == b.itemID and (a.itemLevel or 0) == (b.itemLevel or 0)
    and (a.itemSuffix or 0) == (b.itemSuffix or 0)
end

-- Table rows from browse results (C_AuctionHouse.GetBrowseResults: itemKey, totalQuantity, minPrice).
-- look, all optional functions: info(itemKey) -> { name, quality, isCommodity } or nil while loading;
-- required(itemID) -> required level or nil; value(itemID) -> market value in copper or nil.
-- A result without an item key is left out.
function Browse.rows(results, look)
  look = look or {}
  local rows = {}
  for _, r in ipairs(results or {}) do
    local key = r.itemKey
    if key and key.itemID then
      local info = look.info and look.info(key) or nil
      local value = look.value and look.value(key.itemID) or nil
      local lowest = (r.minPrice or 0) > 0 and r.minPrice or nil
      local name = info and info.name or nil
      rows[#rows + 1] = { itemKey = key, itemID = key.itemID, name = name, sortName = name and name:lower(),
        quality = info and info.quality or nil, commodity = info and info.isCommodity or nil,
        level = look.required and look.required(key.itemID) or nil, listed = r.totalQuantity or 0,
        lowest = lowest, value = value, percent = Browse.percent(lowest, value), own = r.containsOwnerItem }
    end
  end
  return rows
end

local function sortValue(row, column)
  if column == "name" then return row.sortName or (row.name and row.name:lower()) end
  return row[column]
end

-- Sorts rows in place by column ("name", "level", "listed", "lowest", "value" or "percent"), low to high
-- (A to Z), or the other way with descending. Rows without a value for the column go last either way.
-- Ties go by name, then item ID, so the order never jumps between redraws.
function Browse.sort(rows, column, descending)
  if not Browse.SORTS[column] then column = Browse.DEFAULT_SORT end
  table.sort(rows, function(a, b)
    local x, y = sortValue(a, column), sortValue(b, column)
    if x ~= y then
      if x == nil then return false end
      if y == nil then return true end
      if descending then return x > y end
      return x < y
    end
    local an, bn = sortValue(a, "name") or "", sortValue(b, "name") or ""
    if an ~= bn then
      if an == "" then return false end
      if bn == "" then return true end
      return an < bn
    end
    if a.itemID ~= b.itemID then return a.itemID < b.itemID end
    return (a.itemKey.itemLevel or 0) < (b.itemKey.itemLevel or 0)
  end)
  return rows
end

-- The state of the sort after clicking a column's header: a new column sorts its first way, the same
-- column flips. Returns column, descending.
function Browse.click(column, current, descending)
  if column == current then return column, not descending end
  return column, false
end

-- The line under the results, e.g. "212 items for "linen", level 21-30".
function Browse.summary(count, query, truncated)
  local parts = {}
  local text = query and query.searchString or ""
  if text ~= "" then parts[#parts + 1] = string.format("for \"%s\"", text) end
  if query and query.path and ns.BrowseFilters then
    parts[#parts + 1] = "in " .. ns.BrowseFilters.label(query.path)
  end
  local lo, hi = query and query.minLevel or 0, query and query.maxLevel or 0
  if lo > 0 and hi > 0 then
    parts[#parts + 1] = lo == hi and ("level " .. lo) or string.format("level %d-%d", lo, hi)
  elseif lo > 0 then
    parts[#parts + 1] = "level " .. lo .. " and up"
  elseif hi > 0 then
    parts[#parts + 1] = "up to level " .. hi
  end
  local line = string.format("%d %s", count, count == 1 and "item" or "items")
  if #parts > 0 then line = line .. " " .. table.concat(parts, ", ") end
  if truncated then line = line .. " (the first ones only: search for something narrower to see the rest)" end
  return line
end

ns.Browse = Browse
return Browse
