# 0001. Native SwiftUI app generated with XcodeGen, no dependencies

- Status: Accepted
- Date: 2026-10-14

## Context

Crafty Controller already ships a Progressive Web App. A second web wrapper would add little and risks App Review guideline 4.2 ("minimum functionality"). The app must be small, auditable and private.

## Decision

- Native SwiftUI, iOS 17+, `@Observable`, Swift Charts, `async/await`.
- The Xcode project is generated from `project.yml` with XcodeGen; `Kurafuto.xcodeproj` is not committed.
- No third-party dependencies. Personal build settings live in a gitignored `BuildConfig.local.xcconfig`.

## Alternatives considered

- **Web wrapper / WKWebView around the panel** – rejected: duplicates the PWA, weak App Review position, no native features.
- **Cross-platform (Flutter, React Native)** – rejected: extra toolchain and dependencies for an iOS-only goal.
- **Committed `.xcodeproj`** – rejected: merge conflicts; XcodeGen keeps the build graph reviewable.

## Consequences

Contributors need XcodeGen. Every capability is built with Apple frameworks only, which keeps the privacy manifest and supply chain trivial.
