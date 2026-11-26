# Reading the debug log

Better AH keeps a debug log (#99) when it is on (`/bah debug on`, or Settings > Debugging > Debug log On).

- It lives in SavedVariables: `WTF/Account/<ACCOUNT>/SavedVariables/BetterAH.lua`, under
  `BetterAHDB.debugLog.lines`, oldest line first. The client writes the file on `/reload` and logout only,
  so ask the player to `/reload` before reading it. A crash loses the lines since the last write.
- Each line is `#<session> HH:MM:SS.mmm [what] text`. The session number goes up on every login or reload;
  each session starts with a `[session]` line naming the character, realm, client build and start time.
  Times are the player's local time.
- `[MARK]` lines are the player's own notes (`/bah mark <note>`), written even while the log is off. Search
  for them first: they flag the moment something went wrong.
- Other kinds: `ui` (clicks, wheel turns, Enter, with the view), `view`, `browse` (snipe checks and Browse
  searches, with the query and result count), `search` (one item's listings), `buy`, `post`, `scan`,
  `snipe` (the snipe session log), `event` (auction house answers and errors), `blocked` (actions the game
  blocked for this addon), `error` (Lua errors naming BetterAH), `command` and `chat` (`/bah` commands and
  what they printed, so `/bah bags` output lands here).
- The same line repeated is folded into one with `(xN, last <time>)`. The last 4000 lines are kept.
