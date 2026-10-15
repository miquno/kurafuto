# KurafutoWidgets/ (widget extension)

Home Screen and Lock Screen widgets. They only read the snapshot the app writes into the App Group container (`WidgetSnapshot`, ADR 0009); they never contact a panel and have no token.

## Map

| File | Owns |
|---|---|
| `KurafutoWidgets.swift` | Widget bundle: `ServerWidget` (small, circular, rectangular; server chosen with `SelectServerIntent`), `PanelWidget` (medium list), `SnapshotProvider`, `ServerEntity` |
| `WidgetViews.swift` | The widget views and their previews |

Shared with the app through `project.yml`: `Core/Storage/WidgetSnapshot.swift` (snapshot, store, `ServerLink`), `Core/Models/ServerStats.swift` (`ServerStatus`), `DesignSystem/Palette.swift` (colors and fonts without app state) and `Resources/Localizable.xcstrings`.

## Rules

- Read only `WidgetSnapshotStore`. No networking, no Keychain, no `UserDefaults`; a new data field goes into `WidgetSnapshot` and needs the ADR's data list, `PRIVACY.md` and the threat model updated.
- Never show player names, panel addresses or usernames.
- Respect `isPrivate` with `.privacySensitive`, so content stays hidden on a locked device when the app lock is on.
- Home Screen colors come from `Palette` with the snapshot's mode and accent; Lock Screen widgets use system styles and `.widgetAccentable()`.
- The app reloads timelines when the snapshot changes; timelines have one entry and `.never` as policy.
