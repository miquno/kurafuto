# Kurafuto

**Your self-hosted game servers, in your pocket.** · [getkurafuto.app](https://getkurafuto.app)

Kurafuto is an unofficial native iOS app for [Crafty Controller 4](https://craftycontrol.com) panels: start and stop servers, watch the live console, manage players, schedules, backups, files, webhooks, users and roles – everything the web dashboard can do, built for the iPhone.

> Kurafuto is not affiliated with or endorsed by Arcadia Technology, Mojang or Microsoft.

## Privacy first

- **No data collection.** No analytics, crash reporters, ads or tracking SDKs. No developer server.
- **One network peer:** the panel you add. Nothing else is contacted.
- **Secrets stay on the device:** tokens in the Keychain (this device only); passwords are never stored.
- **Self-signed panels** are trusted only after you confirm the certificate fingerprint – App Transport Security stays on.
- **No dependencies:** only Apple frameworks.

Details: [Privacy policy](https://getkurafuto.app/privacy/) · [Threat model](docs/security/threat-model.md)

## Status

Early development (0.1). The full UI runs on a mock service; the live API integration is being verified endpoint by endpoint. See [ROADMAP.md](ROADMAP.md) and [CHANGELOG.md](CHANGELOG.md).

## Getting started

Requirements: macOS, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
cp BuildConfig.local.example.xcconfig BuildConfig.local.xcconfig   # optional: your team ID
xcodegen generate
open Kurafuto.xcodeproj
```

The `Kurafuto` scheme launches with `-mock`, so the app runs on realistic sample data without a panel. Without `-mock`, onboarding also offers **Try the Demo**.

## Features

| Panel area | Screen | Mock | Live |
|---|---|---|---|
| Sign-in (password, 2FA, API token) | `OnboardingView` | ✅ | ✅ |
| Dashboard: status, players, CPU/RAM, quick actions | `DashboardView` | ✅ | ✅ |
| Start / stop / restart / kill / backup / clone / update JAR | `DashboardView`, `ServerDetailView` | ✅ | ✅ |
| Live metrics chart | `ServerDetailView` | ✅ | ✅ |
| Console and commands | `ConsoleView` | ✅ | polling (WebSocket ⚠️) |
| Logs | `LogsView` | ✅ | ✅ |
| Players: op, kick, ban, whitelist | `PlayersView` | ✅ | ✅ |
| Schedules (interval, weekday, cron, chained) | `SchedulesView` | ✅ | ✅ / list ⚠️ |
| Backups (configs, restore, delete) | `BackupsView` | ✅ | ⚠️ |
| Files and `server.properties` editor | `FileBrowserView`, `PropertiesEditorView` | ✅ | ⚠️ |
| Webhooks | `WebhooksView` | ✅ | ✅ |
| Server configuration | `ServerSettingsView` | ✅ | ✅ |
| Create server (Java, Bedrock) | `CreateServerView` | ✅ | ✅ |
| Users and roles | `AdminView` | ✅ | ✅ |
| Host metrics, announcements | `PanelOverviewView` | ✅ | ✅ |

⚠️ = endpoint exists in the panel but is missing from the official OpenAPI spec; see [docs/api/crafty-api-v2.md](docs/api/crafty-api-v2.md).

## Repository layout

```
Kurafuto/           App sources (App, Core, DesignSystem, Features, Resources)
KurafutoTests/      Unit tests
Configs/            Shared xcconfig (local overrides are gitignored)
site/               Static website for getkurafuto.app (GitHub Pages)
docs/               ADRs, security, API map, App Store notes
scripts/            Repository tooling (DCO check)
.github/            CI, templates, code owners
```

Start with [AGENTS.md](AGENTS.md) and [ARCHITECTURE.md](ARCHITECTURE.md).

## Contributing and security

- [CONTRIBUTING.md](CONTRIBUTING.md) – workflow, Conventional Commits, DCO sign-off
- [SECURITY.md](SECURITY.md) – report vulnerabilities privately

## License

[MIT](LICENSE) © miquno and Kurafuto contributors. See [NOTICE](NOTICE).
