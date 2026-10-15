# 0008. No trademark registration

- Status: Accepted
- Date: 2026-10-14

## Context

ADR 0007 excludes the name "Kurafuto" and the app icon from the MIT licence and recommended registering "Kurafuto" as a trademark before 1.0, because only a registered mark makes that exclusion reliably enforceable. Kurafuto is a small, free hobby app; the maintainer does not want the cost and effort of a registration.

## Decision

- No trademark registration for "Kurafuto" or the icon. This replaces the registration bullet in ADR 0007.
- The exclusion of name and icon from the MIT licence stays; it states the intent and asks forks to use their own name and icon.
- The register search before release stays: it checks that nobody else already holds "Kurafuto" for software, so the app does not infringe someone else's mark.

## Alternatives considered

- **Register a word mark at the DPMA** – not chosen: fees and effort out of proportion for a free hobby app.

## Consequences

- Against an identical fork, the project can rely on asking politely, App Store guideline 4.1 (copycats) and, in clear cases, unfair-competition law (UWG); there is no trademark to enforce.
- If the app grows or someone copies it, a registration can still be filed later through a new ADR.
