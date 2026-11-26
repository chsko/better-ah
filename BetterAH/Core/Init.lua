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
    BetterAHDB.posting = BetterAHDB.posting or {}
    if ns.Posting then ns.posting = ns.Posting.Settings.new(BetterAHDB.posting) end
    BetterAHDB.disenchant = BetterAHDB.disenchant or {}
    ns.disenchant = BetterAHDB.disenchant
    BetterAHDB.fullScan = BetterAHDB.fullScan or {}
    if ns.auctionAPI then ns.auctionAPI:useStore(BetterAHDB.fullScan) end
    self:UnregisterEvent("ADDON_LOADED")
  end
end)
