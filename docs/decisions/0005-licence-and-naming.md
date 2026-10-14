# 0005. MIT licence and the name "Kurafuto"

- Status: Accepted; licence scope amended by [0007](0007-name-and-icon-outside-mit.md) (name and icon not under MIT)
- Date: 2026-10-14

## Context

Crafty Controller is GPL-3.0-or-later. Kurafuto only uses its HTTP API and contains none of its code, so it is a separate work. GPL terms conflict with App Store distribution terms. App Review guideline 4.1(c) forbids another developer's product name in an app's name or icon without approval; "Minecraft" is a Mojang trademark.

## Decision

- Licence: MIT (same as Onihayo). No code, assets or text from Crafty Controller are copied into the repository.
- Name: **Kurafuto** (クラフト, Japanese for the generic word "craft"), without "Controller" to keep distance from "Crafty Controller". Store name "Kurafuto – Server Panel".
- Compatibility is stated descriptively ("Compatible with Crafty Controller 4", "unofficial") in the description only, never in name, icon or keywords.

## Alternatives considered

- **GPL-3.0** – rejected: App Store distribution conflicts.
- **Names containing "Crafty" or misspellings of it** – rejected: guideline 4.1 and trademark risk.

## Consequences

Before release: check DPMA/EUIPO registers and App Store availability for "Kurafuto" (`docs/app-store/legal-and-naming.md`). If Arcadia Technology grants permission, the listing may mention Crafty more prominently via a new ADR.
