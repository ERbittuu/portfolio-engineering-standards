# AI agent skills

Vendored skills for AI assistants (Claude Code, Cursor, any Agent
Skills-compatible tool) that are useful across every app in the
portfolio.

## aso/ — App Store Optimization & app marketing

16 hand-picked skills vendored from https://github.com/Eronred/aso-skills
(MIT — see `aso/LICENSE`) — only the ones useful for this portfolio
(solo iOS dev, organic growth, subscriptions): aso-audit,
keyword-research, metadata-optimization, localization,
screenshot-optimization, app-icon-optimization, category-positioning,
competitor-analysis, rating-prompt-strategy, review-management,
seasonal-aso, app-launch, app-rejection-recovery, paywall-optimization,
subscription-lifecycle, monetization-strategy. Dropped upstream skills:
Android, paid UA/ads, attribution, and Appeeky-API-dependent analytics.
The kept frameworks work fully offline — no network or API key needed.

## Install on a new Mac

```sh
mkdir -p ~/.claude/skills
cp -R skills/aso/* ~/.claude/skills/
```

Skills then trigger automatically in any repo when a matching topic
comes up (e.g. "optimize my subtitle" → metadata-optimization).

To refresh from upstream: clone the source repo and re-copy `skills/`
over `skills/aso/`, keeping the LICENSE.
