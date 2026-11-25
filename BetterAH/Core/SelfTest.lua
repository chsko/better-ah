-- A tiny check runner for `/bah selftest`. Pure: checks receive the game
-- environment and the addon namespace as arguments, so specs pass fakes.
local _, ns = ...
ns = ns or {}

local SelfTest = {}
SelfTest.__index = SelfTest

function SelfTest.new()
  return setmetatable({ checks = {} }, SelfTest)
end

-- fn(env, ns) returns status ("pass", "fail" or "info") and a detail string.
function SelfTest:add(name, fn)
  self.checks[#self.checks + 1] = { name = name, fn = fn }
end

function SelfTest:run(env, addon)
  local results = {}
  for _, check in ipairs(self.checks) do
    local ok, status, detail = pcall(check.fn, env, addon)
    if not ok then
      status, detail = "fail", "error: " .. tostring(status)
    end
    if status ~= "pass" and status ~= "fail" and status ~= "info" then
      detail = "check returned unknown status " .. tostring(status) .. (detail and (": " .. tostring(detail)) or "")
      status = "fail"
    end
    results[#results + 1] = { name = check.name, status = status, detail = tostring(detail or "") }
  end
  return results
end

function SelfTest.format(results)
  local lines, counts = {}, { pass = 0, fail = 0, info = 0 }
  for _, r in ipairs(results) do
    lines[#lines + 1] = string.format("[%s] %s: %s", r.status:upper(), r.name, r.detail)
    counts[r.status] = (counts[r.status] or 0) + 1
  end
  lines[#lines + 1] = string.format("Better AH self-test: %d passed, %d failed, %d info",
    counts.pass, counts.fail, counts.info)
  return lines
end

ns.SelfTest = SelfTest
return SelfTest
