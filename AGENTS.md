# AGENTS.md

Entry point for anyone – human or coding agent – changing Kurafuto. This file is the canonical source of repository rules. It stays short: detailed guidance lives in folder-local `AGENTS.md` files next to the code and in `docs/`. `CLAUDE.md` files only import the `AGENTS.md` beside them; never put rules in them.

## Project snapshot

- Kurafuto is an unofficial native iOS client for self-hosted **Crafty Controller 4** panels: everything the web dashboard can do, on the iPhone.
- Product principles: privacy by design (we collect nothing), native over web wrapper, safe by default for destructive actions, works without a server thanks to a full mock.
- Stack: Swift 5.10, SwiftUI, iOS 17+, `@Observable`, Swift Charts, XcodeGen. **No third-party dependencies.** Rationale: `docs/decisions/0001-native-swiftui-and-xcodegen.md`.
- Delivery follows `ROADMAP.md`. Every milestone leaves a working app.

## Workflow for every change

1. Read this file, then the `AGENTS.md` of every folder you will touch.
2. Read `ROADMAP.md` and select **one** coherent roadmap item. Read its acceptance criteria.
3. Inspect existing code before writing new code. Reuse what exists.
4. Implement the smallest complete solution. No speculative abstractions.
5. Add or update tests that verify behavior. New service behavior needs both `MockCraftyService` and `LiveCraftyService` support.
6. Build and run the smallest relevant test slice (see Commands).
7. Update docs only where behavior or architecture changed. Add user-visible changes to `CHANGELOG.md` under `## Unreleased`.
8. Tick the `ROADMAP.md` item only when it is genuinely complete. Then stop.

## Where to look

- `ARCHITECTURE.md` – layers, module boundaries, data flow
- `ROADMAP.md` – milestones, acceptance criteria
- `CONTRIBUTING.md` – branches, commits, DCO, pull requests
- `PRIVACY.md` – the user-facing privacy policy; mirrored at https://getkurafuto.app/privacy/ (`site/`)
- `SECURITY.md` and `docs/security/threat-model.md` – vulnerability reporting, trust boundaries, mitigations
- `docs/decisions/` – architecture decision records (ADRs)
- `docs/api/crafty-api-v2.md` – endpoint map, ✅ documented vs ⚠️ unverified
- `docs/app-store/` – naming, legal notes, store listing
- Folder-local docs: `Kurafuto/AGENTS.md`, `KurafutoTests/AGENTS.md`, `site/AGENTS.md`, `scripts/AGENTS.md`, `.github/AGENTS.md`

## Engineering rules

- The UI depends only on the `CraftyService` protocol. Never call `APIClient` from a view.
- Use `@Observable`, `NavigationStack`, `async/await`. No `ObservableObject`, no Combine pipelines without a reason.
- No force unwraps (`!`, `try!`, `as!`) outside tests.
- Validate everything that comes from the panel: it is untrusted input (lenient decoding, no HTML rendering, no unchecked file paths).
- Do not silently swallow errors that the user must know about; show them. Never log tokens, passwords, panel URLs or console output.
- Destructive actions (stop, kill, delete, restore) always require confirmation.
- Keep comments minimal: only non-obvious constraints, quirks, or the reason for a surprising choice.
- User-facing strings are written in English and translated in `Kurafuto/Resources/Localizable.xcstrings` (German, Japanese, Simplified Chinese). A new string needs all three translations in the same pull request; CI checks it with `scripts/check-localizations.sh`.

## Privacy rules (non-negotiable)

- Kurafuto collects **no** data. No analytics, crash reporters, ads, tracking SDKs, remote config or "phone home".
- The **only** network peer is the panel the user adds. Adding any other host (avatars, update checks, fonts, link previews) requires an ADR, an update to `PRIVACY.md`, `docs/security/threat-model.md` and `PrivacyInfo.xcprivacy` in the same pull request.
- Secrets live in the Keychain (`ThisDeviceOnly`), never in `UserDefaults`, files, logs or screenshots.
- Never weaken App Transport Security globally. Self-signed panels are trusted only by explicit certificate pinning after user confirmation (ADR 0004).

## Dependencies

- None today. Before adding one, write an ADR (purpose, maintenance, licence, size, privacy impact, alternatives). Pin exact versions. No automated update bots.

## Git and safety

- Branches: `feat/`, `fix/`, `docs/`, `ci/`, `refactor/`, `test/`, `chore/`. Conventional Commits. Every commit signed off (`git commit -s`).
- Commit identity: `miquno <35491275+miquno@users.noreply.github.com>`. Never commit a private email address.
- Never force-push shared branches, never `--no-verify`, never commit secrets, team IDs or provisioning profiles (`BuildConfig.local.xcconfig` is gitignored).
- Ask before destructive, irreversible or externally visible actions (publishing, App Store submission, deleting data).
- Temporary files go in `scratch/` (gitignored).

## Commands

```bash
xcodegen generate

xcodebuild build -project Kurafuto.xcodeproj -scheme Kurafuto \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

xcodebuild test -project Kurafuto.xcodeproj -scheme Kurafuto \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:KurafutoTests/MockServiceTests -quiet
```
