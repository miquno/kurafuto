# 0009. Widgets read a cached snapshot from an App Group

- Status: Accepted
- Date: 2026-10-15

## Context

Home Screen and Lock Screen widgets run in a separate extension process. To show server status and players they need data from the panel. Fetching it themselves would put the panel token into a second process (shared Keychain access group) and send requests to the panel in the background, outside the app's pinned session and app lock. Lock Screen widgets also render while the device is locked.

## Decision

- The widgets never contact the panel and get no token. The app writes a `WidgetSnapshot` after each successful refresh of the Servers tab, and the widgets only read it.
- The snapshot holds the panel's display name, and per server its id, name, status, online/maximum player counts, version, CPU and RAM with a downsampled last hour (at most 24 points) and the `-Xmx` limit, the names of up to eight players online (each cut to 32 characters), and the date and configuration name of the newest backup archive. It also holds the time of the values, the app's theme mode and accent color, and whether the app lock is on. It never holds the panel address, the username, tokens, console output or files.
- It is a JSON file in the App Group container `group.dev.miquno.kurafuto`, written atomically with `completeUntilFirstUserAuthentication` file protection, so Lock Screen widgets can read it after the first unlock. It is part of the device's own backup like other app data and never leaves the device otherwise.
- The app writes right away when status, player counts, player names, versions or backups change, and otherwise at most every five minutes, so live CPU and RAM do not reload the widgets on every poll; then it reloads the widget timelines. Signing out of a panel or switching panels deletes the file.
- The extra values come from requests the app already makes: the last hour of every server is loaded once per load of the Servers tab, and the newest backup only while a backup widget is placed (`WidgetCenter` configurations). Without placed widgets nothing extra is requested.
- Player names appear only on Home Screen widgets and are always marked privacy-sensitive, so iOS hides them on a locked device (for example in StandBy). Lock Screen widgets show counts, never names.
- When the app lock is on, widget content is marked privacy-sensitive, so iOS hides it on a locked device.
- Tapping a widget opens `kurafuto://server/<id>`, optionally with `/console` or `/details`. The app only opens a server it already lists; a link can never trigger an action.

## Alternatives considered

- **Widgets fetch from the panel** – rejected: the token would be shared with the extension, requests would run in the background without the app lock, and every widget refresh would hit the panel.
- **Shared `UserDefaults` suite** – rejected: no per-file protection class and a required-reason API in both bundles; a single file is easier to reason about and to delete.
- **No player names at all** – the first version of this ADR. Amended on the maintainer's widget design (2026-10-15): names on the Home Screen only, always privacy-sensitive, never on the Lock Screen.

## Consequences

- Widgets show values as old as the app's last refresh; every widget shows the time of its values.
- A new field in `WidgetSnapshot` is a new stored data category on the device and needs this ADR, `PRIVACY.md` and the threat model updated.
- Builds need the App Group capability for the app and the extension (automatic signing adds it).
