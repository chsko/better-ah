-- Load an addon file the way the WoW client does: with (addonName, ns) as varargs.
local M = {}

function M.load(path, ns)
  ns = ns or {}
  local chunk = assert(loadfile(path))
  chunk("BetterAH", ns)
  return ns
end

return M
