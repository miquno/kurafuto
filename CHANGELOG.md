# Changelog

All notable user-facing changes to Kurafuto are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows [Semantic Versioning](https://semver.org/).

## Unreleased

- Demo mode with sample servers, live console, backups, schedules, users and roles – no panel required.
- Sign in to a Crafty Controller 4 panel with a password (plus 2FA) or an API token. Self-signed panels can be trusted after checking the certificate fingerprint.
- Dashboard with status, players, CPU and RAM for every server; start, stop, restart, kill, back up, clone and update servers.
- Server detail with live CPU/RAM chart, console with quick commands and history, logs, players, schedules, backups, files, server.properties editor, webhooks and configuration.
- Create Java and Bedrock servers.
- Minecraft EULA: when a Java server can't start because its EULA isn't accepted, Kurafuto asks and starts it after you accept. You can also accept the EULA right away when creating a Java server.
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
- Demo mode: start times and console timestamps follow the current clock instead of fixed dates, and starting or stopping a demo server updates its start time.
- Clearer errors: screens tell apart an unreachable panel, a signed-out session and missing rights. When live values stop updating, the dashboard and server screen say so. Failed start, stop, restart and kill actions show why.
- When the panel signs you out (expired token or "Sign Out All Sessions"), Kurafuto asks you to sign in again to the same panel instead of failing quietly.
- Failed saves and actions everywhere (schedules, webhooks, files, backups, players, console commands, users and roles, server settings, announcements) now show why instead of failing silently. The file editors only allow saving once the file has loaded, so a failed load can no longer empty a file.
- Schedules work on real panels: new schedules (every few minutes, hours or days at a set time, cron, or after another schedule) are saved the way the panel's own task runner expects. Before, the panel rejected them. Crafty's API cannot list schedules, so on a real panel the Schedules screen adds new ones and links to the web panel to view, edit or delete them.
- Backups work on real panels: create, edit and delete backup configurations, back up now with the chosen configuration, and restore an archive over the current files or into an emptied server folder (both ask first). "Back Up Now" now also works on Crafty 4.7, where it used to fail inside the panel. Crafty 4.7 cannot list archives over the API, so the Backups screen links to the web panel there. Schedules can now run backups too.
- Files and server.properties work on real panels: browse server folders, open and save text files up to 1 MB, create folders and delete files and folders. If someone changed a file on the panel after you opened it, Kurafuto asks before overwriting it. The server.properties editor now keeps the file's comments and order and has a search field. The upload button, which did nothing yet, is gone until uploads arrive.
- Works with Crafty Controller 4.7 and later; sign-in, servers, live values, start/stop/restart, console, logs, schedules, backups and files are verified against real panels.
