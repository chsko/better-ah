-- When to scan the auction house by itself (#30): pure rules, no WoW API.
-- A scan runs when the auction house is open and the last full scan of the market is INTERVAL old (or
-- there is none). A failed scan tries again after RETRIES[1], then RETRIES[2], and so on. Never within
-- THROTTLE of the last answered full scan of any addon (#114): the server answers one per 15 minutes per
-- account and ignores the rest, so asking sooner only ends in a timeout. Whether an unanswered request
-- restarts the server's 15 minutes isn't known, so after a failure of ours the retry also waits THROTTLE
-- from the last request (by anyone).
local _, ns = ...
ns = ns or {}

local AutoScan = {}

AutoScan.INTERVAL = 15 * 60
AutoScan.RETRIES = { 2 * 60, 5 * 60, 15 * 60 }
AutoScan.THROTTLE = 15 * 60
-- Seconds after the auction house opens before a due scan starts (Blizzard's window opens first), how
-- long a scan waits behind a post or a buy, and how often the title's countdown is redrawn.
AutoScan.FIRST_DELAY, AutoScan.BUSY_DELAY, AutoScan.TICK = 2, 10, 30

-- Seconds until the next scan is due (0: now). lastScan: when the last full scan finished (nil: never).
-- failures: scans failed in a row since the last good one, the last at failedAt.
-- askedAt: when any addon last asked the server for a full scan; answeredAt: when the server last answered
-- one (nil: not known). With no answer known, the last request counts.
function AutoScan.wait(lastScan, now, failures, failedAt, askedAt, answeredAt)
  local from = answeredAt or askedAt
  if failures and failures > 0 and askedAt and (not from or askedAt > from) then from = askedAt end
  return math.max(AutoScan.ownWait(lastScan, now, failures, failedAt), AutoScan.throttleWait(now, from))
end

function AutoScan.ownWait(lastScan, now, failures, failedAt)
  if failures and failures > 0 then
    local retry = AutoScan.RETRIES[math.min(failures, #AutoScan.RETRIES)]
    return math.max(0, (failedAt or now) + retry - now)
  end
  if not lastScan then return 0 end
  return math.max(0, lastScan + AutoScan.INTERVAL - now)
end

-- Seconds until the server answers a full scan again.
function AutoScan.throttleWait(now, askedAt)
  if not askedAt then return 0 end
  return math.max(0, askedAt + AutoScan.THROTTLE - now)
end

-- "in 11 min", "in a moment" (under a minute).
function AutoScan.within(seconds)
  if seconds < 60 then return "in a moment" end
  return "in " .. math.ceil(seconds / 60) .. " min"
end

-- The scan state for the title bar. s = { open, scanning, lastScan, now, failures, failedAt, why, held,
-- askedAt, askedBy, answeredAt }. held: a due scan waits for something else (sniping) to finish.
-- askedAt/askedBy: the last full scan request, "us" or "other"; answeredAt: the server's last answer.
function AutoScan.status(s)
  if s.scanning then return "Scanning the auction house..." end
  local last = s.lastScan and ("Scanned " .. ns.Time.ago(s.lastScan, s.now) .. ".") or "Not scanned yet."
  if not s.open then return last .. " Open the auction house to scan." end
  local due = AutoScan.wait(s.lastScan, s.now, s.failures, s.failedAt, s.askedAt, s.answeredAt)
  if s.held and due == 0 then return last .. " Next scan when sniping stops." end
  local wait = AutoScan.within(due)
  if s.failures and s.failures > 0 then
    return string.format("Scan failed: %s. Trying again %s.", s.why or "no answer", wait)
  end
  -- Held back by another addon's request, not by our own last scan: say so, or the wait looks wrong.
  if s.askedBy == "other" and due > AutoScan.ownWait(s.lastScan, s.now) then
    return string.format("%s Another addon ran a full scan %s. Next scan %s.", last, ns.Time.ago(s.askedAt, s.now),
      wait)
  end
  return last .. " Next scan " .. wait .. "."
end

ns.AutoScan = AutoScan
return AutoScan
