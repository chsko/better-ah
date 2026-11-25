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

ns.Money = Money
return Money
