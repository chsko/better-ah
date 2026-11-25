-- Slash commands. Thin glue between the chat frame and the pure modules.
local _, ns = ...

local function say(line)
  DEFAULT_CHAT_FRAME:AddMessage("|cfff2c94cBetter AH|r " .. line)
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

SLASH_BETTERAH1 = "/bah"
SlashCmdList.BETTERAH = function(msg)
  local name = (msg or ""):match("^%s*(%S*)"):lower()
  local handler = commands[name] or commands.help
  handler()
end
