-- Slash commands. Thin glue between the chat frame and the pure modules.
local addonName, ns = ...

-- Chat treats "|" as an escape, so it is doubled in the line to print it as typed.
-- What it prints also goes in the debug log (#99), so /bah bags and /bah selftest reach a bug report.
local function say(line)
  DEFAULT_CHAT_FRAME:AddMessage("|cfff2c94cBetter AH|r " .. (tostring(line):gsub("|", "||")))
  if ns.DebugHooks then ns.DebugHooks.add("chat", "%s", tostring(line)) end
end

local commands = {}

commands.help = function()
  say("/bah selftest - check what this client supports (never buys, posts or cancels)")
  say("/bah bags - list what the Post view sees in your bags (for bug reports)")
  say("/bah debug on|off - keep a log of what you do in Better AH, saved on /reload or logout")
  say("/bah mark <note> - add a note to the debug log, such as what just went wrong")
  say("/bah quote [raw] - ask for a price on 1 of the commodity open in Browse (never buys; for bug reports)")
  say("/bah help - show this list")
end

commands.selftest = function()
  local results = ns.Probes.suite():run(_G, ns)
  for _, line in ipairs(ns.SelfTest.format(results)) do
    say(line)
  end
end

commands.bags = function()
  local view = ns.window and ns.window.postView
  if view then
    for _, line in ipairs(view:debugLines()) do say(line) end
  end
  if ns.PostingAPI then
    if not (ns.postingAPI and ns.postingAPI.open) then
      say("The auction house is closed, so nothing reads as sellable: open it first.")
    end
    for _, line in ipairs(ns.PostingAPI.slotReport(_G)) do say(line) end
  end
end

commands.debug = function(rest)
  local l = ns.debugLog
  if not (l and ns.DebugHooks) then return say("The debug log isn't loaded yet.") end
  local arg = rest:lower()
  if arg == "on" or arg == "off" then
    ns.DebugHooks.setOn(_G, arg == "on")
    if ns.window and ns.window.settingsView then ns.window.settingsView:render() end
  elseif arg == "clear" then
    l:clear()
    return say("The debug log is empty now.")
  end
  say(string.format("The debug log is %s (%d lines). It's saved on /reload or logout. %s", l:isOn() and "on" or "off",
    l:count(), l:isOn() and "/bah debug off stops it." or "/bah debug on starts it."))
end

commands.mark = function(rest)
  local l = ns.debugLog
  if not l then return say("The debug log isn't loaded yet.") end
  l:mark(rest)
  say(l:isOn() and "Marked in the debug log."
    or "Marked. The debug log is off, so only the note is kept: /bah debug on.")
end

-- /bah quote (#112): asks for a price on 1 of the commodity open in Browse, from a key press instead of the Buy
-- click, to find out why the game blocks Buy. "/bah quote" goes through Browse's own code; "/bah quote raw"
-- calls the game directly from here, as other addons do, and drops the quote once it comes. Never buys.
local StartCommoditiesPurchase = C_AuctionHouse and C_AuctionHouse.StartCommoditiesPurchase
local RAW_WAIT = 10
local rawWatch, rawArmed

local function disarm()
  rawArmed = nil
  if rawWatch then rawWatch:UnregisterAllEvents() end
end

commands.quote = function(rest)
  local view = ns.window and ns.window.browseView
  local item = view and view.item
  local row = item and item.row
  if not (row and item.list and item.list.commodity and item:showing()) then
    return say("Open a commodity in Browse first, then type /bah quote (or /bah quote raw).")
  end
  local api = ns.browseAPI
  local why = api and api:blocked()
  if why then return say("Not now: " .. why .. ".") end
  if rest:lower() ~= "raw" then
    say("Asking for a price on 1 " .. tostring(row.name) .. " through Browse (from a key press). "
      .. "It shows in Browse; Confirm would buy it, Cancel drops it.")
    item.commodityControls.quantity:SetText("1")
    item:quantityChanged()
    return item:quote()
  end
  if not StartCommoditiesPurchase then return say("C_AuctionHouse.StartCommoditiesPurchase is missing.") end
  if rawArmed then return say("Still waiting for the last raw quote.") end
  if not rawWatch then
    rawWatch = CreateFrame("Frame")
    rawWatch:SetScript("OnEvent", function(_, event, a, b)
      if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if a ~= nil and a ~= addonName then return end
        say("Raw quote: " .. event .. " " .. tostring(b) .. ".")
        return disarm()
      end
      disarm()
      if event == "COMMODITY_PRICE_UPDATED" then
        say(string.format("Raw quote came: %s each, %s in all. Dropped, nothing bought.", tostring(a), tostring(b)))
        if C_AuctionHouse.CancelCommoditiesPurchase then C_AuctionHouse.CancelCommoditiesPurchase() end
      else
        say("Raw quote: " .. event .. ".")
      end
    end)
  end
  for _, e in ipairs({ "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE", "AUCTION_HOUSE_CLOSED",
    "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    rawWatch:RegisterEvent(e)
  end
  local token = {}
  rawArmed = token
  C_Timer.After(RAW_WAIT, function()
    if rawArmed == token then
      disarm()
      say("Raw quote: no answer in " .. RAW_WAIT .. " s.")
    end
  end)
  say("Asking the game directly for a price on 1 " .. tostring(row.name) .. " (item " .. tostring(row.itemID) .. ")...")
  StartCommoditiesPurchase(row.itemID, 1)
end

SLASH_BETTERAH1 = "/bah"
SlashCmdList.BETTERAH = function(msg)
  local name, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  name = name:lower()
  if ns.DebugHooks and name ~= "mark" then ns.DebugHooks.add("command", "/bah %s", msg or "") end
  local handler = commands[name] or commands.help
  handler(rest)
end
