-- Character records (spec #1): what each of the player's characters owns, kept across sessions.
-- Pure: the character tracker (Game/CharacterTracker.lua) reads the game and hands plain counts in.
--
-- Stored in BetterAHDB.characters as
--   chars[key] = { name, faction, bags = { [item] = count }, bank = {...}, auctions = {...},
--                  seen = { bags = time, bank = time, auctions = time } }
--   names[item] = item name (shared by all characters)
local _, ns = ...
ns = ns or {}

local CharacterRecords = {}
CharacterRecords.__index = CharacterRecords

-- Where a character keeps items, in the order the detail panel lists them.
CharacterRecords.PLACES = { "bags", "bank", "auctions" }
local isPlace = { bags = true, bank = true, auctions = true }

function CharacterRecords.new(store)
  store = store or {}
  store.chars = store.chars or {}
  store.names = store.names or {}
  return setmetatable({ store = store }, CharacterRecords)
end

local function record(self, key)
  local c = self.store.chars[key]
  if not c then
    c = { seen = {} }
    self.store.chars[key] = c
  end
  return c
end

-- info: { name = "Thrall", faction = "Horde" }; missing fields are left as they were.
function CharacterRecords:setCharacter(key, info)
  local c = record(self, key)
  for k, v in pairs(info) do c[k] = v end
end

-- Replaces what a character has in one place. items is an array of { item, count, name };
-- counts for the same item are added up. Returns false for an unknown place.
function CharacterRecords:setPlace(key, place, items, time)
  if not isPlace[place] then return false end
  local counts = {}
  for _, it in ipairs(items) do
    local count = tonumber(it.count) or 0
    if it.item ~= nil and count > 0 then
      counts[it.item] = (counts[it.item] or 0) + count
      if it.name and it.name ~= "" then self.store.names[it.item] = it.name end
    end
  end
  local c = record(self, key)
  c[place] = counts
  c.seen[place] = time
  return true
end

-- Characters sorted by name: { key, name, faction, seen = { bags, bank, auctions } }.
function CharacterRecords:characters()
  local out = {}
  for key, c in pairs(self.store.chars) do
    out[#out + 1] = { key = key, name = c.name or key, faction = c.faction, seen = c.seen }
  end
  table.sort(out, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.key < b.key
  end)
  return out
end

-- How many of an item each character has: total, and an array sorted by character name of
--   { key, name, total, bags, bank, auctions }
-- holding only characters that have some.
function CharacterRecords:count(item)
  local total, by = 0, {}
  for _, ch in ipairs(self:characters()) do
    local c = self.store.chars[ch.key]
    local row = { key = ch.key, name = ch.name, total = 0 }
    for _, place in ipairs(CharacterRecords.PLACES) do
      local n = c[place] and c[place][item] or 0
      row[place] = n
      row.total = row.total + n
    end
    if row.total > 0 then
      by[#by + 1] = row
      total = total + row.total
    end
  end
  return total, by
end

-- Every item any character owns, sorted by name (unnamed last), as
--   { item, name, total, characters = number of characters that have it }
-- nameOf(item), if given, names items with no stored name.
function CharacterRecords:items(nameOf)
  local totals, holders = {}, {}
  for _, c in pairs(self.store.chars) do
    local mine = {}
    for _, place in ipairs(CharacterRecords.PLACES) do
      for item, n in pairs(c[place] or {}) do
        totals[item] = (totals[item] or 0) + n
        mine[item] = true
      end
    end
    for item in pairs(mine) do holders[item] = (holders[item] or 0) + 1 end
  end
  local out, sortKey = {}, {}
  for item, total in pairs(totals) do
    local name = self.store.names[item]
    if not name and nameOf then
      name = nameOf(item)
      if type(name) ~= "string" or name == "" then name = nil end
    end
    local row = { item = item, name = name, total = total, characters = holders[item] }
    out[#out + 1] = row
    sortKey[row] = name and name:lower()
  end
  table.sort(out, function(a, b)
    local ak, bk = sortKey[a], sortKey[b]
    if (ak == nil) ~= (bk == nil) then return ak ~= nil end
    if ak and ak ~= bk then return ak < bk end
    return tostring(a.item) < tostring(b.item)
  end)
  return out
end

ns.CharacterRecords = CharacterRecords
return CharacterRecords
