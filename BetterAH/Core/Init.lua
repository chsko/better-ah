-- Addon entry point. Every file receives (addonName, ns) from the client;
-- ns is the shared private namespace for the addon's modules.
local addonName, ns = ...

ns.name = addonName
ns.modules = ns.modules or {}

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, loadedName)
  if event == "ADDON_LOADED" and loadedName == addonName then
    BetterAHDB = BetterAHDB or {}
    ns.db = BetterAHDB
    BetterAHDB.prices = BetterAHDB.prices or {}
    if ns.PriceDB then ns.prices = ns.PriceDB.new(BetterAHDB.prices) end
    BetterAHDB.characters = BetterAHDB.characters or {}
    if ns.CharacterRecords then ns.characters = ns.CharacterRecords.new(BetterAHDB.characters) end
    self:UnregisterEvent("ADDON_LOADED")
  end
end)
