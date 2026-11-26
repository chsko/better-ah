-- Search history (#129): the searches Browse has run, newest first, with pinned ones kept at the top.
-- Pure: the store is a plain table (BetterAHDB.browse.history) and times are passed in. The view lists
-- the entries, reruns one on a click, and pins or removes them. Specs in spec/search_history_spec.lua.
local _, ns = ...
ns = ns or {}

local SearchHistory = {}
SearchHistory.__index = SearchHistory

SearchHistory.RECENT = 15 -- unpinned searches kept; the oldest goes when a new one comes
SearchHistory.PINNED = 30 -- pinned searches allowed

local function trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function whole(n)
  n = tonumber(n)
  if not n or n <= 0 or n ~= math.floor(n) then return 0 end
  return n
end

-- A search as history keeps it, from what Browse searched: { text, minLevel, maxLevel, category,
-- filters }. minLevel/maxLevel 0 mean no limit. category, optional: { label = "Armor › Mail", ... }
-- with whatever else the view needs to search it again. filters, optional: a list of
-- { key = "usable", label = "usable by me" }, in the order they are shown.
function SearchHistory.normalize(search)
  search = search or {}
  local lo, hi = whole(search.minLevel), whole(search.maxLevel)
  if lo > 0 and hi > 0 and lo > hi then lo, hi = hi, lo end
  local out = { text = trim(search.text), minLevel = lo, maxLevel = hi }
  if type(search.category) == "table" and trim(search.category.label) ~= "" then
    local category = {}
    for k, v in pairs(search.category) do category[k] = v end
    out.category = category
  end
  local filters = {}
  for _, f in ipairs(type(search.filters) == "table" and search.filters or {}) do
    if type(f) == "table" and f.key ~= nil then
      filters[#filters + 1] = { key = tostring(f.key), label = tostring(f.label or f.key) }
    end
  end
  if #filters > 0 then out.filters = filters end
  return out
end

-- Whether a search lists everything with no limits at all: such searches are not worth remembering.
function SearchHistory.blank(search)
  search = SearchHistory.normalize(search)
  return search.text == "" and search.minLevel == 0 and search.maxLevel == 0 and not search.category
    and not search.filters
end

-- A string that is the same for the same search: text ignores case, filters ignore order.
function SearchHistory.key(search)
  search = SearchHistory.normalize(search)
  local filters = {}
  for i, f in ipairs(search.filters or {}) do filters[i] = f.key end
  table.sort(filters)
  return table.concat({ search.text:lower(), search.minLevel, search.maxLevel,
    search.category and search.category.label or "", table.concat(filters, ",") }, "\31")
end

-- The level range as words: "level 21-30", "level 40", "level 30 and up", "up to level 20", or nil.
function SearchHistory.levels(lo, hi)
  lo, hi = whole(lo), whole(hi)
  if lo > 0 and hi > 0 then return lo == hi and ("level " .. lo) or string.format("level %d-%d", lo, hi) end
  if lo > 0 then return "level " .. lo .. " and up" end
  if hi > 0 then return "up to level " .. hi end
  return nil
end

-- Two lines for a search in the list: its name ("Everything" when no text) and what else limited it
-- ("Armor › Mail · level 21-30 · usable by me", or "all categories").
function SearchHistory.label(search)
  search = SearchHistory.normalize(search)
  local name = search.text ~= "" and search.text or "Everything"
  local parts = {}
  if search.category then parts[#parts + 1] = search.category.label end
  parts[#parts + 1] = SearchHistory.levels(search.minLevel, search.maxLevel)
  for _, f in ipairs(search.filters or {}) do parts[#parts + 1] = f.label end
  if #parts == 0 then return name, "all categories" end
  return name, table.concat(parts, " · ")
end

-- History over store, a list of { search, at, pinned } kept newest first. Entries that aren't
-- well formed (a hand-edited or old SavedVariables file) are dropped.
function SearchHistory.new(store)
  store = store or {}
  local self = setmetatable({ store = store }, SearchHistory)
  local seen, keep, pins = {}, {}, 0
  for _, e in ipairs(store) do
    if type(e) == "table" and type(e.search) == "table" then
      local search = SearchHistory.normalize(e.search)
      local key = SearchHistory.key(search)
      if not seen[key] and not SearchHistory.blank(search) then
        seen[key] = true
        local pinned = e.pinned == true and pins < SearchHistory.PINNED or nil
        if pinned then pins = pins + 1 end
        keep[#keep + 1] = { search = search, at = tonumber(e.at) or 0, pinned = pinned }
      end
    end
  end
  for i = #store, 1, -1 do store[i] = nil end
  for i, e in ipairs(keep) do store[i] = e end
  self:trim()
  return self
end

function SearchHistory:find(key)
  for i, e in ipairs(self.store) do
    if SearchHistory.key(e.search) == key then return i, e end
  end
  return nil
end

-- Drops the oldest unpinned searches past the limit.
function SearchHistory:trim()
  local recent = 0
  local store = self.store
  local i = 1
  while i <= #store do
    if not store[i].pinned then
      recent = recent + 1
      if recent > SearchHistory.RECENT then
        table.remove(store, i)
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end
end

-- Remembers a search that just ran, at time now. The same search again moves to the top with its new
-- time and keeps its pin. A blank search is not remembered. Returns the entry, or nil.
function SearchHistory:add(search, now)
  search = SearchHistory.normalize(search)
  if SearchHistory.blank(search) then return nil end
  local i, old = self:find(SearchHistory.key(search))
  if i then table.remove(self.store, i) end
  local entry = { search = search, at = now or 0, pinned = old and old.pinned or nil }
  table.insert(self.store, 1, entry)
  self:trim()
  return entry
end

-- Forgets a search, pinned or not. Returns whether it was there.
function SearchHistory:remove(key)
  local i = self:find(key)
  if not i then return false end
  table.remove(self.store, i)
  return true
end

-- Pins or unpins a search. Returns true, or false and why (not there, or too many pinned).
-- An unpinned search goes to the top of the recent ones, so it can't be the one pushed out.
function SearchHistory:pin(key, on)
  local _, e = self:find(key)
  if not e then return false, "That search is no longer in the history." end
  on = on and true or nil
  if on and not e.pinned then
    local pinned = 0
    for _, other in ipairs(self.store) do
      if other.pinned then pinned = pinned + 1 end
    end
    if pinned >= SearchHistory.PINNED then
      return false, string.format("You can pin up to %d searches. Unpin one first.", SearchHistory.PINNED)
    end
  end
  if not on and e.pinned then
    table.remove(self.store, (self:find(key)))
    table.insert(self.store, 1, e)
  end
  e.pinned = on
  self:trim()
  return true
end

-- Forgets every unpinned search.
function SearchHistory:clearRecent()
  local store = self.store
  for i = #store, 1, -1 do
    if not store[i].pinned then table.remove(store, i) end
  end
end

-- The entries for the list: pinned ones, then recent ones, each newest first. Each is
-- { key, search, at, pinned, name, detail }.
function SearchHistory:list()
  local pinned, recent = {}, {}
  for _, e in ipairs(self.store) do
    local name, detail = SearchHistory.label(e.search)
    local item = { key = SearchHistory.key(e.search), search = e.search, at = e.at, pinned = e.pinned == true,
      name = name, detail = detail }
    if e.pinned then pinned[#pinned + 1] = item else recent[#recent + 1] = item end
  end
  return pinned, recent
end

ns.SearchHistory = SearchHistory
return SearchHistory
