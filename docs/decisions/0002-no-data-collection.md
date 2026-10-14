# 0002. No data collection; the user's panel is the only network peer

- Status: Accepted
- Date: 2026-10-14

## Context

Kurafuto handles credentials for servers that people run at home. Users of self-hosted software choose it for control and privacy. Any third-party call (avatars, analytics, crash reports, update checks) would leak IP addresses, panel usage or player names.

## Decision

- Kurafuto collects no data and runs no developer-operated server.
- The only network peer is the panel the user adds.
- Player avatars are local initials; skin services such as mc-heads.net are not used.
- Tokens are stored in the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; passwords are never persisted.
- The panel list lives in Application Support with complete file protection, never in Documents.
- An app-switcher privacy cover hides panel addresses and console output.
- `PrivacyInfo.xcprivacy` declares no tracking and no collected data types. App Store privacy label: "Data Not Collected".

## Alternatives considered

- **Crash reporting / analytics SDK** – rejected: third-party data flow; Xcode Organizer crash logs (opt-in by the user via Apple) are sufficient.
- **Player heads from a skin API** – rejected: sends player names and the user's IP to a third party.

## Consequences

Adding any new network host or stored data category requires a new ADR plus updates to `PRIVACY.md`, the threat model and the privacy manifest in the same pull request. Push notifications would need a relay and are therefore deferred (see `ROADMAP.md` → Later).
