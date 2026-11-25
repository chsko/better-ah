-- Market key: one string per market, built from realm, ruleset and faction (ADR 0003).
-- Pure: no WoW API calls. The game adapter (Game/AuctionAPI.lua) supplies the parts.
local _, ns = ...
ns = ns or {}

local MarketKey = {}

-- Not "|": WoW chat treats it as an escape character, so a key with "|" prints garbled.
local SEP = "/"

local function part(value, what)
  value = value == nil and "" or tostring(value)
  if value:find(SEP, 1, true) then error(what .. " must not contain '" .. SEP .. "'", 3) end
  return value
end

-- parts = { realm = "...", ruleset = "...", faction = "..." }. Realm may be empty: Forever's
-- GetRealmName() returns "" (ADR 0004). Ruleset and faction are required.
function MarketKey.build(parts)
  local realm = part(parts.realm, "realm")
  local ruleset = part(parts.ruleset, "ruleset")
  local faction = part(parts.faction, "faction")
  if ruleset == "" or faction == "" then error("a market key needs a ruleset and a faction", 2) end
  return realm .. SEP .. ruleset .. SEP .. faction
end

-- Returns the parts table, or nil when the string is not a market key.
function MarketKey.parse(key)
  if type(key) ~= "string" then return nil end
  local realm, ruleset, faction = key:match("^([^/]*)/([^/]+)/([^/]+)$")
  if not realm then return nil end
  return { realm = realm, ruleset = ruleset, faction = faction }
end

-- A short label for players, for example "PvP, Alliance". A ruleset that is only a number (or
-- "default") reads "ruleset 1, Horde".
function MarketKey.describe(key)
  local parts = MarketKey.parse(key)
  if not parts then return tostring(key) end
  local ruleset = parts.ruleset
  if ruleset:match("^%d+$") or ruleset == "default" then ruleset = "ruleset " .. ruleset end
  local label = ruleset .. ", " .. parts.faction
  if parts.realm ~= "" then label = parts.realm .. ", " .. label end
  return label
end

ns.MarketKey = MarketKey
return MarketKey
