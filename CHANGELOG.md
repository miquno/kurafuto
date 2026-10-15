# Changelog

All notable user-facing changes to Kurafuto are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows [Semantic Versioning](https://semver.org/).

## Unreleased

- Demo mode with sample servers, live console, backups, schedules, users and roles – no panel required.
- Sign in to a Crafty Controller 4 panel with a password (plus 2FA) or an API token. Self-signed panels can be trusted after checking the certificate fingerprint.
- Dashboard with status, players, CPU and RAM for every server; start, stop, restart, kill, back up, clone and update servers.
- Server detail with live CPU/RAM chart, console with quick commands and history, logs, players, schedules, backups, files, server.properties editor, webhooks and configuration.
- Create Java and Bedrock servers.
- Users and roles with a per-server permission matrix.
- Host metrics and panel announcements.
- Multiple panels, Face ID setting, and a privacy cover in the app switcher.
- App icon: a pixel-art server rack.
- Creating and cloning servers and the Admin tab are hidden when your panel account lacks the rights for them.
- Settings link to the website and privacy policy at getkurafuto.app.
- New "Instrument" design on every screen: dark, gray and light modes, and your own accent color for the app, CPU, RAM, players and storage (Settings → Appearance).
- Animated gauges, live charts and build-up animations; with Reduce Motion they become simple fades.
- The console shows new lines instantly over the panel's WebSocket and falls back to polling when the connection is unavailable. It keeps the last 1,000 lines.
- App lock: with "Lock with Face ID" on, Kurafuto asks for Face ID (or Touch ID or the device passcode) when it opens or returns from the background, and before stopping, killing, deleting or restoring. Turning the lock on or off also needs Face ID.
- Deleting schedules, webhooks, files and folders now asks for confirmation first (and Face ID when the app lock is on).
- Works with Crafty Controller 4.7 and later; sign-in, servers, live values, start/stop/restart, console and logs are verified against real panels.
