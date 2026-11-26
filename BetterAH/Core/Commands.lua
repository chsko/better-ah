-- Slash commands. Thin glue between the chat frame and the pure modules.
local _, ns = ...

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

SLASH_BETTERAH1 = "/bah"
SlashCmdList.BETTERAH = function(msg)
  local name, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  name = name:lower()
  if ns.DebugHooks and name ~= "mark" then ns.DebugHooks.add("command", "/bah %s", msg or "") end
  local handler = commands[name] or commands.help
  handler(rest)
end
