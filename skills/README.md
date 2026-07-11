# AI agent skills

Vendored skills for AI assistants (Claude Code, Cursor, any Agent
Skills-compatible tool) that are useful across every app in the
portfolio.

## aso/ — App Store Optimization & app marketing

39 skills vendored from https://github.com/Eronred/aso-skills
(MIT — see `aso/LICENSE`). Frameworks for keyword research, metadata
optimization, localization, screenshots, competitor analysis, launch,
monetization, and more. Some skills can pull live data through the
Appeeky API if a key is configured; the frameworks work without it.

## Install on a new Mac

```sh
mkdir -p ~/.claude/skills
cp -R skills/aso/* ~/.claude/skills/
```

Skills then trigger automatically in any repo when a matching topic
comes up (e.g. "optimize my subtitle" → metadata-optimization).

To refresh from upstream: clone the source repo and re-copy `skills/`
over `skills/aso/`, keeping the LICENSE.
