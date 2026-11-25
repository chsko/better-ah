-- Pure helpers for copper amounts. No WoW API calls here, so this file is
-- unit tested with busted (see spec/money_spec.lua).
local _, ns = ...
ns = ns or {}

local Money = {}

local COPPER_PER_SILVER = 100
local COPPER_PER_GOLD = 10000

-- Split a copper amount into gold, silver and copper.
function Money.split(copper)
  copper = math.floor(copper or 0)
  local gold = math.floor(copper / COPPER_PER_GOLD)
  local silver = math.floor((copper % COPPER_PER_GOLD) / COPPER_PER_SILVER)
  return gold, silver, copper % COPPER_PER_SILVER
end

-- Format a copper amount as "12g 3s 4c", dropping leading zero parts.
function Money.format(copper)
  if not copper or copper <= 0 then return "0c" end
  local g, s, c = Money.split(copper)
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "g" end
  if g > 0 or s > 0 then parts[#parts + 1] = s .. "s" end
  parts[#parts + 1] = c .. "c"
  return table.concat(parts, " ")
end

-- The most a typed amount may be: the auction house's own limit of 9,999,999g 99s 99c.
Money.MAX = 99999999999

-- Read what a player typed as a copper amount: "12g 3s 4c", "3s", "1g5s", or a bare number of copper.
-- Returns nil for anything else.
function Money.parse(text)
  if type(text) ~= "string" then return nil end
  text = text:lower():gsub("%s+", "")
  if text == "" then return nil end
  if text:match("^%d+$") then return tonumber(text) end
  local total, rest = 0, text
  for _, unit in ipairs({ { "g", COPPER_PER_GOLD }, { "s", COPPER_PER_SILVER }, { "c", 1 } }) do
    local n, after = rest:match("^(%d+)" .. unit[1] .. "(.*)$")
    if n then
      total = total + tonumber(n) * unit[2]
      rest = after
    end
  end
  if rest ~= "" or total == 0 and not text:match("^0") then return nil end
  if total > Money.MAX then return nil end
  return total
end

ns.Money = Money
return Money
