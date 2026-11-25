-- Slash commands. Thin glue between the chat frame and the pure modules.
local _, ns = ...

-- Chat treats "|" as an escape, so it is doubled in the line to print it as typed.
local function say(line)
  DEFAULT_CHAT_FRAME:AddMessage("|cfff2c94cBetter AH|r " .. (tostring(line):gsub("|", "||")))
end

local commands = {}

commands.help = function()
  say("/bah selftest - check what this client supports (never buys, posts or cancels)")
  say("/bah help - show this list")
end

commands.selftest = function()
  local results = ns.Probes.suite():run(_G, ns)
  for _, line in ipairs(ns.SelfTest.format(results)) do
    say(line)
  end
end

-- PROTOTYPE (#23): /bah proto a|b|c switches the sidebar style. Not for main.
commands.proto = function(msg)
  local style = (msg or ""):lower():match("^%s*%S+%s+(%a)%s*$")
  if not (style == "a" or style == "b" or style == "c") or not ns.window then
    return say("/bah proto a|b|c - a: red buttons, b: flat list, c: Blizzard's AH category buttons")
  end
  local note = ns.window:setStyle(style)
  say("Sidebar style " .. style .. (note and (" (" .. note .. ")") or ""))
end

-- PROTOTYPE (#23): /bah frame portrait|basic picks the outer frame; it takes effect after /reload.
commands.frame = function(msg)
  local kind = (msg or ""):lower():match("^%s*%S+%s+(%a+)%s*$")
  if kind ~= "portrait" and kind ~= "basic" then
    return say("/bah frame portrait|basic - portrait: like Blizzard's AH, basic: the old dark frame")
  end
  if ns.db then ns.db.protoFrame = kind end
  say("Frame " .. kind .. " after /reload")
end

-- PROTOTYPE (#23): /bah show opens the window without an auctioneer, for design screenshots.
commands.show = function()
  if not ns.window then return say("The window isn't loaded.") end
  ns.window:build():Show()
  ns.window:renderView()
end

SLASH_BETTERAH1 = "/bah"
SlashCmdList.BETTERAH = function(msg)
  local name = (msg or ""):match("^%s*(%S*)"):lower()
  local handler = commands[name] or commands.help
  handler(msg)
end
