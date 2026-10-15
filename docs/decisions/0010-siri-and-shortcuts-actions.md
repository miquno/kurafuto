# 0010. Siri and Shortcuts actions run inside the app

- Status: Accepted
- Date: 2026-10-15

## Context

The roadmap asks for App Intents: start and stop a server and ask for the player count from Siri, Shortcuts and automations. These run without the app's screens, possibly by voice or on a schedule, and stopping a server disconnects players. The panel token must not leave the app.

## Decision

- Three App Intents in the app target: Start Server, Stop Server, Player Count, plus App Shortcuts phrases ("Start <server> in Kurafuto") in English, German, Japanese and Simplified Chinese.
- They run in the app's process with the active panel's existing client. The token stays in the Keychain and the app; iOS, Siri and Shortcuts only receive server ids, server names and the results shown in the dialogs.
- Every action needs an unlocked device (`authenticationPolicy = .requiresAuthentication`).
- Stop is destructive: iOS asks for confirmation first (with the server's name and a destructive "Stop" button on iOS 18 and later, a generic question on iOS 17), and with the app lock on, Face ID or the passcode is required as well. iOS refuses Face ID to apps in the background (LocalAuthentication error -1004, "Caller is not running foreground"), so with the lock on Stop brings Kurafuto to the front (`continueInForeground` on iOS 26+, `ForegroundContinuableIntent` before), waits up to 30 seconds for the app's lock screen to be unlocked, and then asks for the stop like the app does. Without an unlock, or with a refused check, the action fails with a message; it never skips the check.
- Start is not destructive and needs no extra confirmation, as in the app. Kill, delete and restore are not offered.
- Player Count asks the panel live; it does not read the widget snapshot.
- Without a panel in the app (only the demo), the actions refuse with "Add your panel in Kurafuto first." They act on the panel that is active in the app.
- After the Servers tab loads, the app updates the App Shortcuts parameters, so Siri can match server names.

## Alternatives considered

- **Intents in an extension** – rejected: the extension would need the token through a shared Keychain access group.
- **Kill, restart and console commands** – left out: not on the roadmap, and each would need its own confirmation design.
- **Skip the app lock for Shortcuts** – rejected: the lock exists to stop someone with the unlocked phone from stopping servers.

## Consequences

- Server names reach iOS for Siri and Shortcuts suggestions, processed under Apple's Siri and search privacy terms; Kurafuto itself still sends nothing anywhere but the panel.
- With the app lock on, Stop opens Kurafuto and needs two checks (unlock and stop), the same as stopping inside the app. Verified on the simulator against a local Crafty 4.11 panel: refused or missing Face ID keeps the server running.
