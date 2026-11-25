# Better AH

An auction house addon for World of Warcraft: Forever. Think TradeSkillMaster, with improvements.

## Install

Copy (or symlink) the `BetterAH` folder into `World of Warcraft/_forever_/Interface/AddOns/`.

## Develop

Needs Lua 5.1, [luacheck](https://github.com/lunarmodules/luacheck) and [busted](https://lunarmodules.github.io/busted/).

```sh
luarocks install luacheck && luarocks install busted
luacheck . && busted
```

## How work gets done

Planning happens in GitHub issues, and an agent loop ("Ralph") implements them one at a time.

1. Install the skills once: `claude plugin install mattpocock-skills@claude-plugins-official`.
2. Plan a feature: `/grill-me`, then `/to-spec`, then `/to-tickets`. Tickets get the `ready-for-agent` label.
3. Run the loop: `ralph/once.sh` to watch one iteration, or `ralph/afk.sh 10` to run up to 10 unattended.

See `CLAUDE.md` for the rules the agent follows.
