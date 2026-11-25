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

Work is planned and tracked in GitHub issues using [Matt Pocock's skills](https://github.com/mattpocock/skills),
which are installed in `.claude/skills/`. Update them with `npx skills@latest update`.

A typical feature: `/grill-me` to shape it, `/to-spec` to publish a spec issue, `/to-tickets` to split it
into issues, then `/implement` (one ticket) or `/implement-spec` (the whole spec). `/triage` keeps the
backlog labelled. See `CLAUDE.md` for the rules agents follow.
