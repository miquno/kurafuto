# Kurafuto/ (app target)

All app sources. XcodeGen picks up new files through the folder glob in `project.yml`; just run `xcodegen generate`.

## Map

| Folder | Owns |
|---|---|
| `App/` | `KurafutoApp`, `AppState` (active panel + service + panel rights + app lock), `RootView` (incl. app-switcher privacy cover and lock screen), tabs; `AppLock` (Face ID / passcode via LocalAuthentication), `.destructiveConfirmation` |
| `Core/Models/` | `Codable` models that mirror Crafty's `openapi-spec.yml` (snake_case `CodingKeys`). Tolerant decoding for Crafty's string-typed numbers |
| `Core/Networking/` | `APIClient`: bearer auth, `{status,data}` envelope (`requestUnwrapped` for routes without it), console WebSocket (`token` cookie), ephemeral `URLSession`, certificate pinning delegate |
| `Core/Services/` | `CraftyService` protocol, `LiveCraftyService` (real API, ✅/⚠️ markers), `CraftyConsoleFeed` (WebSocket and `/logs` parsing), `MockCraftyService` + `MockData` |
| `Core/Storage/` | `KeychainStore` (tokens), `InstanceStore` (panel list in Application Support, no secrets) |
| `DesignSystem/` | "Instrument" design: `Appearance` (theme mode + per-metric accent presets, UserDefaults), `Theme` (palette), cards, `IconTile`, `StatusDot`/`StatusBadge`, `RingGauge`/`GaugeTile`, `MeterBar`, `.entrance()` animation, `InstrumentButtonStyle`, `Loadable`/`LoadableView` (problem-specific error states), `StaleValuesBanner`, `.errorAlert`, `ConfirmAction` |
| `Features/<Area>/` | One folder per panel area: Onboarding, Dashboard, ServerDetail, Console, Players, Schedules, Backups, Files, Webhooks, ServerSettings, CreateServer, Admin, Panel, Settings |
| `Resources/` | `PrivacyInfo.xcprivacy`; `Assets.xcassets` (`AppIcon`, single 1024 px image rendered by `scripts/make-app-icon.swift`; `LaunchBackground` = dark `Theme.background`); generated `Info.plist` (gitignored) |

## Rules

- Views talk to `app.service` (a `CraftyService`) only. A new capability is added to the protocol, the live service **and** the mock in the same change.
- `MockData` stays realistic and English; it powers previews, tests, the demo mode and App Review.
- Panel strings (MOTD, logs, file contents) are plain text. Never render them as HTML or `AttributedString(markdown:)`.
- File paths passed to the panel come from the panel's own listings; never build them from free text without validation.
- Destructive actions (stop, kill, delete, restore) use a `ConfirmAction` with `.destructiveConfirmation($confirm)`, or call `app.lock.authorize(_:)` before acting, so the app lock applies.
- Failed actions are shown, not swallowed: catch the error and present it with `.errorAlert($error)`. Loading errors go through `LoadableView`. A rejected token is handled globally (`SignInAgainView`).
- Every `Features/` screen has a `#Preview` backed by `AppState.preview`.
- Colors come from `Theme` only (no hard-coded or system colors in features), so all three theme modes and the user's accent choices apply. Data values use `Font.mono`.
- Lists and forms use `.themedBackground()` and wrap their content in a `Group { … }.themedRows()`; custom screens use `.card()`.
- Motion goes through `.entrance()`, `RingGauge` and `MeterBar`, which respect Reduce Motion. Don't add animations that ignore it.
- Do not add a network host other than the user's panel (see root `AGENTS.md`, privacy rules).
