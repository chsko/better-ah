-- When to scan the auction house by itself (#30): pure rules, no WoW API.
-- A scan runs when the auction house is open and the last full scan of the market is INTERVAL old (or
-- there is none). A failed scan tries again after RETRIES[1], then RETRIES[2], and so on.
local _, ns = ...
ns = ns or {}

local AutoScan = {}

AutoScan.INTERVAL = 15 * 60
AutoScan.RETRIES = { 2 * 60, 5 * 60, 15 * 60 }
-- Seconds after the auction house opens before a due scan starts (Blizzard's window opens first), how
-- long a scan waits behind a post or a buy, and how often the title's countdown is redrawn.
AutoScan.FIRST_DELAY, AutoScan.BUSY_DELAY, AutoScan.TICK = 2, 10, 30

-- Seconds until the next scan is due (0: now). lastScan: when the last full scan finished (nil: never).
-- failures: scans failed in a row since the last good one, the last at failedAt.
function AutoScan.wait(lastScan, now, failures, failedAt)
  if failures and failures > 0 then
    local retry = AutoScan.RETRIES[math.min(failures, #AutoScan.RETRIES)]
    return math.max(0, (failedAt or now) + retry - now)
  end
  if not lastScan then return 0 end
  return math.max(0, lastScan + AutoScan.INTERVAL - now)
end

-- "in 11 min", "in a moment" (under a minute).
function AutoScan.within(seconds)
  if seconds < 60 then return "in a moment" end
  return "in " .. math.ceil(seconds / 60) .. " min"
end

-- The scan state for the title bar. s = { open, scanning, lastScan, now, failures, failedAt, why, held }.
-- held: a due scan waits for something else (sniping) to finish.
function AutoScan.status(s)
  if s.scanning then return "Scanning the auction house..." end
  local last = s.lastScan and ("Scanned " .. ns.Time.ago(s.lastScan, s.now) .. ".") or "Not scanned yet."
  if not s.open then return last .. " Open the auction house to scan." end
  local due = AutoScan.wait(s.lastScan, s.now, s.failures, s.failedAt)
  if s.held and due == 0 then return last .. " Next scan when sniping stops." end
  local wait = AutoScan.within(due)
  if s.failures and s.failures > 0 then
    return string.format("Scan failed: %s. Trying again %s.", s.why or "no answer", wait)
  end
  return last .. " Next scan " .. wait .. "."
end

ns.AutoScan = AutoScan
return AutoScan
