-- Pure time helpers for labels such as "5 min ago".
local _, ns = ...
ns = ns or {}

local Time = {}

-- How long ago `past` was, seen from `now` (both in seconds).
function Time.ago(past, now)
  if not past then return "never" end
  local d = math.max(0, (now or past) - past)
  if d < 60 then return "just now" end
  if d < 3600 then return math.floor(d / 60) .. " min ago" end
  if d < 86400 then return math.floor(d / 3600) .. " h ago" end
  local days = math.floor(d / 86400)
  return days == 1 and "1 day ago" or (days .. " days ago")
end

ns.Time = Time
return Time
