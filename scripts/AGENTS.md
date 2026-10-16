# scripts/

Repository tooling. Scripts here run in CI and are marked in `CODEOWNERS`; review changes with care.

| Script | Purpose |
|---|---|
| `check-dco.sh <base> <head>` | Fails if any non-merge commit lacks a `Signed-off-by` trailer matching its author. Used by `.github/workflows/dco.yml` |
| `check-localizations.sh <derived-data>` | After a build: fails if `Localizable.xcstrings` or `AppShortcuts.xcstrings` misses strings or Siri phrases from the app or widget code (or keeps removed ones), or if one lacks a finished `de`, `ja` or `zh-Hans` translation. Used by `.github/workflows/ci.yml` |
| `make-app-icon.swift <output.png>` | Renders the app icon from its 32×32 pixel map into an opaque 1024 px PNG. Run locally after editing the map; not part of CI |

Rules: `set -euo pipefail`, no network access, no secrets, never interpolate untrusted input into commands.
