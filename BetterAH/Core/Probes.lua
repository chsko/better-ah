-- The checks `/bah selftest` runs inside the client. They only read the game
-- environment; they never buy, post or cancel. Later modules add their own
-- checks with ns.Probes.suite():add(name, fn).
local _, ns = ...
ns = ns or {}

local Probes = {}

local LEGACY_AH = {
  "QueryAuctionItems", "GetNumAuctionItems", "GetAuctionItemInfo", "GetAuctionItemLink",
  "CanSendAuctionQuery", "PostAuction", "StartAuction", "CancelAuction", "PlaceAuctionBid",
  "GetOwnerAuctionItems",
}

local MODERN_AH = {
  "SendBrowseQuery", "GetBrowseResults", "ReplicateItems", "GetNumReplicateItems",
  "GetReplicateItemInfo", "PostItem", "PostCommodity", "CancelAuction", "PlaceBid",
  "StartCommoditiesPurchase", "QueryOwnedAuctions",
}

local function presence(container, names)
  local found, missing = {}, {}
  for _, name in ipairs(names) do
    if container and type(container[name]) == "function" then
      found[#found + 1] = name
    else
      missing[#missing + 1] = name
    end
  end
  return found, missing
end

local function describePresence(found, missing)
  return string.format("found: %s; missing: %s",
    #found > 0 and table.concat(found, ", ") or "none",
    #missing > 0 and table.concat(missing, ", ") or "none")
end

local function call(env, path, ...)
  local fn = env
  for part in path:gmatch("[^.]+") do
    if type(fn) ~= "table" then return nil end
    fn = fn[part]
  end
  if type(fn) ~= "function" then return nil end
  return true, fn(...)
end

local function build()
  local suite = ns.SelfTest.new()

  suite:add("Interface version", function(env)
    local version, buildNumber, _, interface = env.GetBuildInfo()
    return "info", string.format("%s (build %s.%s)", tostring(interface), tostring(version), tostring(buildNumber))
  end)

  suite:add("Realm", function(env)
    return "info", tostring(env.GetRealmName())
  end)

  suite:add("Faction", function(env)
    return "info", tostring((env.UnitFactionGroup("player")))
  end)

  -- Forever replaces realms with rulesets; nobody knows yet which API names
  -- the ruleset, so report every candidate the client answers.
  suite:add("Ruleset hints", function(env)
    local hints = {}
    for _, path in ipairs({
      "C_GameRules.IsHardcoreActive", "C_GameRules.GetActiveGameMode", "C_Seasons.GetActiveSeason",
      "C_Seasons.HasActiveSeason", "C_Realm.GetCurrentRulesetID", "GetCurrentRegionName",
    }) do
      local ok, value = call(env, path)
      if ok then hints[#hints + 1] = path .. "=" .. tostring(value) end
    end
    return "info", #hints > 0 and table.concat(hints, ", ") or "no ruleset API found"
  end)

  suite:add("Legacy AH API", function(env)
    return "info", describePresence(presence(env, LEGACY_AH))
  end)

  suite:add("C_AuctionHouse API", function(env)
    return "info", describePresence(presence(env.C_AuctionHouse, MODERN_AH))
  end)

  suite:add("Auction house API available", function(env)
    local legacy = presence(env, { "QueryAuctionItems" })
    local modern = presence(env.C_AuctionHouse, { "SendBrowseQuery" })
    if #legacy > 0 or #modern > 0 then
      return "pass", (#modern > 0 and "C_AuctionHouse" or "legacy") .. " browse query present"
    end
    return "fail", "neither QueryAuctionItems nor C_AuctionHouse.SendBrowseQuery exists"
  end)

  suite:add("Saved variables", function(_, addon)
    if addon and addon.db then return "pass", "BetterAHDB loaded" end
    return "fail", "BetterAHDB not loaded yet"
  end)

  return suite
end

-- One shared suite per namespace, so other files can add checks to it.
function Probes.suite()
  ns.probeSuite = ns.probeSuite or build()
  return ns.probeSuite
end

ns.Probes = Probes
return Probes
