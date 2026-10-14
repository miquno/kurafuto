# scripts/

Repository tooling. Scripts here run in CI and are marked in `CODEOWNERS`; review changes with care.

| Script | Purpose |
|---|---|
| `check-dco.sh <base> <head>` | Fails if any non-merge commit lacks a `Signed-off-by` trailer matching its author. Used by `.github/workflows/dco.yml` |

Rules: `set -euo pipefail`, no network access, no secrets, never interpolate untrusted input into commands.
