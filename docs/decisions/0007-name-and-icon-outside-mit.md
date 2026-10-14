# 0007. Name and app icon are not covered by the MIT licence

- Status: Accepted
- Date: 2026-10-14

## Context

ADR 0005 put Kurafuto under the MIT licence. MIT grants everyone the right to copy and redistribute "the Software and associated documentation files", which would include the app icon once it is in the repository, and invites forks that ship under the same name and icon. Users could then not tell the original app from a copy in the App Store, and a copy could undermine the privacy promise (ADR 0002).

The icon is pixel art drawn from a pixel map, after a draft made with an AI image generator. Under German law a work needs a human's own intellectual creation to be protected by copyright (§ 2 Abs. 2 UrhG), so whether the icon is protected is uncertain. Name and logo are reliably protected through a registered trademark (MarkenG) and, against confusing imitations, through unfair-competition law (§ 4 Nr. 3, § 5 UWG).

## Decision

- The **source code and documentation** stay under the MIT licence; `LICENSE` keeps the unmodified MIT text.
- The **name "Kurafuto"** and the **app icon** (the image files and the pixel map and palette that render it) are **not licensed under MIT**. All rights reserved. `NOTICE` and `README.md` say so.
- Forks and redistributions may use the code but must use a different name and icon. Saying that a fork is "based on Kurafuto" is fine.
- Before the 1.0 release, register "Kurafuto" as a word mark (and optionally the icon as a figurative mark) at the DPMA or EUIPO, classes 9 and 42, once the register search in `docs/app-store/legal-and-naming.md` is clear.

## Alternatives considered

- **Everything under MIT** – rejected: anyone could publish an identical-looking app under the same name.
- **A separate artwork licence such as CC BY-NC-ND** – rejected: it would still allow redistribution of the unchanged icon, and its protection depends on the same uncertain copyright.
- **Moving the icon out of the public repository** – rejected: the build must work from a clean clone, and CI builds the app.

## Consequences

- Contributors keep all MIT freedoms for code; pull requests that change the icon are still welcome, and the result stays excluded from MIT.
- Real protection starts with the trademark registration; until then the exclusion mainly states intent. If the icon's copyright status matters later (for example in a dispute), ask a lawyer.
