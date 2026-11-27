# Companion app on your PC

The companion app keeps Better AH's sell times data fresh on your PC. It downloads `SellTimes.lua`
from the sell times site into the BetterAH addon folder every hour and at logon, so the in-game hint
is up to date after a `/reload`. Spec #215, ticket #220.

## Install

1. Open the latest **Better AH companion** release on GitHub (Releases, tag `companion-v…`) and
   download both `better-ah-companion.exe` and `better-ah-companion-task.exe` into the same folder.
2. Open a terminal in that folder and run:

   ```powershell
   .\better-ah-companion.exe install
   ```

   The default addon folder is `%USERPROFILE%\better-ah\BetterAH`. If yours is elsewhere, add
   `--target "<path to the BetterAH folder>"`. The folder must contain `BetterAH.toc`.

`install` copies both programs to `%LOCALAPPDATA%\better-ah-companion` (the downloads can be
deleted afterwards), adds a Task Scheduler task called **Better AH sync**, and runs it once.
The task runs hourly at :45 and a minute after you log on, and catches up after the PC was off.
It needs no administrator rights. If Windows refuses with "Access is denied", run the same
command from a terminal opened with "Run as administrator".

## Check it

- Task Scheduler › Task Scheduler Library shows **Better AH sync** with its last run result.
- `%LOCALAPPDATA%\better-ah-companion\sync.log` gets one line per run: `updated`, `unchanged` or
  `error: …`.
- `BetterAH\SellTimes.lua` exists. It is gitignored, so `git status` stays clean.
- In game, `/reload` picks up the new file.

## Sync by hand or remove

```powershell
.\better-ah-companion.exe sync        # download now
.\better-ah-companion.exe uninstall   # remove the task
```

`uninstall` leaves `%LOCALAPPDATA%\better-ah-companion` (the programs and `sync.log`); delete
that folder by hand if you want them gone.

The addon works as before without the file. The sell time hint just doesn't show.

## Publishing a new version (maintainers)

Actions › **Companion release** › Run workflow, with a version like `0.1.0`. It tests, builds
the Windows binaries and creates the `companion-v<version>` release.
