# Contributing to Kurafuto

Thanks for your interest in Kurafuto! This page describes how changes get into the repository. Project rules live in [AGENTS.md](AGENTS.md) and the folder-local `AGENTS.md` files.

## Prerequisites

- macOS with Xcode 16 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

```bash
cp BuildConfig.local.example.xcconfig BuildConfig.local.xcconfig   # optional: your team ID
xcodegen generate
open Kurafuto.xcodeproj
```

The `Kurafuto` scheme starts with `-mock`, so the app runs on sample data without a panel.

## Workflow

1. Pick or open an issue. Work follows [ROADMAP.md](ROADMAP.md); one pull request delivers one roadmap item (or one fix).
2. Branch from `main`: `feat/…`, `fix/…`, `docs/…`, `ci/…`, `refactor/…`, `test/…` or `chore/…`.
3. Make the smallest coherent change. Add or update tests.
4. Build and run the relevant tests (see `AGENTS.md` → Commands).
5. Add user-visible changes to `CHANGELOG.md` under `## Unreleased`.
6. Open a pull request using the template. List only checks you actually ran.

`main` only changes through pull requests. Pull requests are squash-merged, so the title must follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat: add webhook editor`). Required checks: `build-and-test` and `DCO`.

## Privacy

Kurafuto collects no data and talks only to the user's own panel. A pull request that adds a network host, SDK, analytics or new stored data category will not be merged without an ADR and updates to `PRIVACY.md`, `docs/security/threat-model.md` and `PrivacyInfo.xcprivacy`.

## Dependencies

Kurafuto has no third-party dependencies. Do not add one without a written ADR: what it does, why the platform is not enough, maintenance status, licence, size and privacy impact.

## Developer Certificate of Origin

Kurafuto uses the [Developer Certificate of Origin 1.1](https://developercertificate.org/). By signing off a commit you certify that you have the right to submit it under the project's licence.

```bash
git commit -s -m "fix: describe the change"
```

This adds `Signed-off-by: Your Name <your.email@example.com>`, which must match the commit author. Use your GitHub `noreply` address if you do not want to publish your email. To sign off commits on your branch after the fact:

```bash
git rebase --signoff origin/main
git push --force-with-lease
```

## Licensing

Contributions are licensed under the [MIT License](LICENSE). Do not copy code, assets or text from Crafty Controller (GPL-licensed) or any other project into this repository.
