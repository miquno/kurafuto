# Architecture

Kurafuto is a single-target SwiftUI app with no backend of its own and no third-party dependencies. It talks to exactly one kind of server: the Crafty Controller panel that the user adds.

```
┌──────────────────────── iPhone ────────────────────────┐
│ Features/*  (SwiftUI views, one folder per panel area) │
│        │  uses only                                    │
│        ▼                                               │
│ CraftyService (protocol) ◄── AppState picks one:       │
│   ├─ MockCraftyService   demo, previews, tests         │
│   └─ LiveCraftyService ──► APIClient ──HTTPS──────────┼──► User's Crafty panel
│                                 │  (pinned if          │     (API v2, bearer token)
│ Keychain ◄── KeychainStore      │   self-signed)       │
│ App Support ◄── InstanceStore (panel list, no secrets) │
└────────────────────────────────────────────────────────┘
```

## Layers

1. **Features** – screens. They own view state only, call `app.service`, and show errors via `LoadableView`.
2. **Services** – `CraftyService` is the single seam. `LiveCraftyService` maps calls to API v2 endpoints (see `docs/api/crafty-api-v2.md`); `MockCraftyService` simulates the same behavior in memory.
3. **Networking** – `APIClient` handles the `{status, data}` envelope, bearer tokens, errors, and certificate trust.
4. **Storage** – `KeychainStore` for tokens, `InstanceStore` for the list of panels.

## Data ownership

| Data | Where it lives | Leaves the device? |
|---|---|---|
| Panel token / API key | Keychain, `AfterFirstUnlockThisDeviceOnly` | Only to that panel, in the `Authorization` header |
| Password, 2FA code | Memory during sign-in only | Only to that panel's login endpoint |
| Panel list (name, URL, username, pinned cert hash) | `Application Support/instances.json`, complete file protection | Never (part of the user's own device backup) |
| App preferences (Face ID toggle, refresh interval) | `UserDefaults` | Never |
| Server data, logs, files | Memory while displayed | Never stored by Kurafuto |

Kurafuto has no server, no analytics and no third-party network calls. See `PRIVACY.md` and ADR 0002.

## Live updates

`LiveCraftyService.consoleStream` loads the console backlog from `/logs`, then follows the panel's undocumented WebSocket `/ws` – the same one the web panel uses, on the same host and pinned session, authenticated with the `token` cookie. Parsing lives in `CraftyConsoleFeed`. If the socket is refused, drops or stops answering pings, the stream falls back to polling `/logs` every 2 seconds. Starting a server also opens the socket briefly, because the panel reports a missing Minecraft EULA only there. Stats are still polled from `/stats`. Everything stops when the view disappears (`.task` cancellation).

## Errors

`APIClient.failure` maps panel answers to `CraftyError`, and `Error.panelProblem` sorts every error into offline, session expired, permission denied or other. `LoadableView`, `StaleValuesBanner` and `.errorAlert` show the matching message. A rejected token makes the active client post `.panelSessionExpired` (no payload); `RootView` then shows `SignInAgainView`, which replaces the token in the Keychain.

## App lock

`AppState.lock` (`AppLock`) wraps LocalAuthentication's `deviceOwnerAuthentication`, so Face ID or Touch ID falls back to the device passcode. When the lock is on, `RootView` covers the app with `LockView` at launch and after the scene went to the background (not on `.inactive`, which the Face ID prompt itself triggers). Destructive actions go through `.destructiveConfirmation` or `lock.authorize(_:)`. iOS answers only yes or no; no biometric data reaches the app.

## Decisions

See `docs/decisions/`.
