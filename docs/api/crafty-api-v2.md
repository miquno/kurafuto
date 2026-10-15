# Crafty API v2 → CraftyService

Based on `openapi-spec.yml` v2.0.1 (docs.craftycontrol.com). Auth: `Authorization: Bearer <token>`.
Responses: `{"status":"ok","data":…}` / `{"status":"error","error":"CODE","error_data":"…"}`.

**Minimum supported panel: Crafty Controller 4.7.0.** "Live" marks calls exercised with `LiveCraftyService`
against local test panels **4.7.0** and **4.11.0** (official Docker images, Paper 1.21.4 server, 2026-10-14).

| CraftyService | Method & path | Docs | Live |
|---|---|---|---|
| login | `POST /api/v2/auth/login` {username,password,totp?} | ✅ | ✅ |
| invalidateAllSessions | `POST /api/v2/auth/invalidate_tokens` | ✅ | – |
| healthCheck | `GET /api/v2/crafty/check` | ✅ | ✅ |
| servers | `GET /api/v2/servers` | ✅ | ✅ |
| server | `GET /api/v2/servers/{id}` | ✅ (example in spec is wrong) | ✅ |
| createServer | `POST /api/v2/servers` | ✅ | ✅ Paper download |
| updateServer | `PATCH /api/v2/servers/{id}` | ✅ | – |
| deleteServer | `DELETE /api/v2/servers/{id}` | ✅ | – |
| send(action) | `POST /api/v2/servers/{id}/action/{start_server…}[/{action_id}]` | ✅ | start, stop, restart, kill ✅ · backup names the default config ✅ · clone, update – |
| acceptEULA | `POST /api/v2/servers/{id}/action/eula` (writes `eula.txt`, then starts the server) | ⚠️ action name from panel source | ✅ |
| sendCommand | `POST /api/v2/servers/{id}/stdin` (text/plain, no leading /) | ✅ | ✅ |
| logs | `GET /api/v2/servers/{id}/logs?file=&colors=&raw=&html=` | ✅ | ✅ live buffer and file |
| stats | `GET /api/v2/servers/{id}/stats` | ✅ | ✅ stopped and running |
| schedules | none: `GET /api/v2/servers/{id}/tasks` is an empty stub (500) | ❌ not in spec | ✅ not listable, returns nil |
| create/update/deleteSchedule | `POST …/tasks`, `PATCH/DELETE …/tasks/{taskID}` | ✅ | ✅ interval, daily time, cron, chained |
| webhooks | `GET /api/v2/servers/{id}/webhook` | ✅ | – |
| saveWebhook | `POST /api/v2/servers/{id}/webhook` · `PATCH /api/v2/server/{id}/webhook/{wid}` | ✅ (note singular "server") | – |
| panelAccess | `GET /api/v2/users/@me` (superuser) + `GET /api/v2/users/@me/permissions` | ✅ | ✅ superuser, no rights, mask `101` |
| users / saveUser / deleteUser | `/api/v2/users`, `/api/v2/users/{id}` | ✅ | – |
| roles / saveRole / deleteRole | `/api/v2/roles`, `/api/v2/roles/{id}` | ✅ | – |
| hostStats | `GET /metrics/host` (OpenMetrics text) | ✅ | – |
| announcements / clear | `GET/POST /api/v2/crafty/announcements` | ✅ | – |
| backupConfigs | `GET /api/v2/servers/{id}/backups` (no envelope) | ⚠️ routes from panel source | ✅ |
| saveBackupConfig | `POST …/backups` · `PATCH …/backups/backup/{backup_id}` | ⚠️ | ✅ create, patch |
| deleteBackupConfig | `DELETE …/backups/backup/{backup_id}` (default config: 405 `NOT_ALLOWED`) | ⚠️ | ✅ |
| backupFiles | `GET …/backups/backup/{backup_id}/files` (no envelope, 4.11+; 405 on 4.7) | ⚠️ | ✅ 4.11 list · 4.7 returns nil |
| startBackup | `POST …/action/backup_server/{backup_id}` | ✅ | ✅ |
| restoreBackup | `POST …/backups/backup/{backup_id}` {filename, inPlace} | ⚠️ | ✅ in place and replace |
| deleteBackup | `DELETE …/backups/backup/{backup_id}/files` {filename} | ⚠️ | ✅ |
| listFiles | `POST /api/v2/servers/{id}/files` {path} (folder) | ⚠️ routes from panel source | ✅ |
| readFile | `POST …/files` {path} (file) → {content, attributes.modified_epoch} | ⚠️ | ✅ |
| writeFile | `PATCH …/files` {path, contents, modified_epoch, overwrite} (409 if changed since) | ⚠️ | ✅ incl. conflict |
| createFolder | `PUT …/files/create` {parent, name, directory} | ⚠️ | ✅ |
| deleteFile | `DELETE …/files` {file_system_objects: [{filename}]} | ⚠️ | ✅ files and folders |
| consoleStream | `GET /logs` backlog, then WebSocket `/ws?page=/panel/server_detail&page_query_params=?id={id}` | ⚠️ undocumented, polling `/logs` as fallback | ✅ socket and fallback |

## Quirks found on real panels

Captured responses from 4.11.0 are pinned in `KurafutoTests/CraftyResponseTests.swift`.

- **Login:** `"totp": null` is rejected as `INCORRECT_CREDENTIALS` (4.11.0). Leave the key out when there is no code (`LoginRequest`).
- **Stats:** values Crafty does not know yet (stopped or still booting server) arrive as the string `"False"`: `started`, `version`, `desc`, `players`. `icon` can be `""`. The app treats both as missing.
- **Stats `mem`:** 4.7.0 sends a formatted string (`"1.4GB"`), 4.11.0 a byte count (`1480200192.0`).
- **Stats `started`:** `yyyy-MM-dd HH:mm:ss` in **UTC**, while `created` is ISO 8601 in panel-local time.
- **Logs:** HTML-escaped (Python `html.escape`) unless `raw=true`, which also keeps ANSI codes. The app unescapes the five entities and shows plain text.
- **Console WebSocket:** not in the spec; ported from `websocket_handler.py` and `ServerOutBuf.new_line_handler`. Auth is the `token` cookie only (no header, no query); an invalid token is accepted at the handshake and closed right after. The server pushes `{"event":"vterm_new_line","data":{"line":…}}` – the line is HTML-escaped, wrapped in `<span>` highlight tags and ends with `<br />`; 4.11.0 batches up to 20 stdout lines per message, separated by `\n`. Only new lines are sent, so the backlog comes from `/logs`. 4.11.0 sends console lines only to users with the server's TERMINAL permission. Other events on the same socket (`update_server_details`, `notification`, …) are ignored for now. Pings are answered; the panel sends nothing while a server is idle.
- **Logs buffer:** `/logs` without `file` returns a sliding window of `virtual_terminal_lines` (default 70), so polling diffs by overlap, not by count.
- **EULA:** a Java server only starts with `eula=true` in `eula.txt`. `start_server` still answers `ok`; the refusal arrives about a second later only as WebSocket event `{"event":"send_eula_bootbox","data":{"id":…}}` to the user who pressed start. The app opens the socket before sending `start_server`, waits up to 4 s (console output ends the wait early) and then asks; `action/eula` accepts and starts in one step. Creating a Java server accepts `agree_to_eula` in `download_jar_create_data` (4.7.0 and 4.11.0), which writes the file up front.
- **Backup:** `action/backup_server` without an id uses the default backup config on 4.11.0. On 4.7.0 it answers `ok` but the backup fails inside the panel (`BackupsDoesNotExist`); it needs `action/backup_server/{backup_id}`. `send(.backup)` therefore looks up the default config first and always names it.
- **Backup routes:** success answers of `GET …/backups`, `GET …/backups/backup/{id}` and `GET …/files` have **no** `{status,data}` envelope (`APIClient.requestUnwrapped`); errors still do. `GET …/backups` is an object keyed by backup id; `excluded_dirs` is one comma-separated string; `max_backups` 0 keeps everything. Missing BACKUP permission answers 400 `NOT_AUTHORIZED`.
- **Backup configs:** bodies are validated with `additionalProperties: false`. Only superusers may send `backup_location` (non-superusers get `INVALID_JSON_SCHEMA`; the panel sets `backups/{server_id}` for them). `backup_name` needs at least 3 characters. Deleting a config keeps its archives; 4.11.0 also deletes the config's schedules, 4.7.0 leaves them behind without a target. The default config cannot be deleted (405).
- **Backup archives:** only 4.11+ lists them, as full paths of `*.zip` in `{backup_location}/{backup_id}/` without size or date; snapshot configs are not listed at all. Names are `yyyy-MM-dd_HH-mm-ss.zip` in the panel host's local time; the panel only restores names of that shape, so Kurafuto drops anything else and sends back just the name. Restore stops the server and answers `ok` right away; the result arrives later as a WebSocket notification. `inPlace: false` empties the server folder first (verified on 4.7.0 with a marker file).

- **Schedules:** there is no list endpoint. `GET …/tasks` is an unimplemented stub that answers 500; only the web panel's server-rendered page lists schedules. `GET …/tasks/{taskID}` exists but returns the bare row without the `{status,data}` envelope, and `POST …/tasks` returns `"schedule_id": null` for disabled or chained schedules, so ids cannot be collected either. Kurafuto therefore only creates schedules and links to the web panel for the rest.
- **Schedule body:** validated with `additionalProperties: false`, so `schedule_id` or `next_run` make the request fail (`INVALID_JSON_SCHEMA`). `interval_type` is `minutes`, `hours`, `days`, `reaction` (chained) or `""` (cron); weekdays are not accepted. The task runner executes `command`: for start, stop, restart and backup it must be `start_server`, `stop_server`, `restart_server` or `backup_server`, which the web panel fills in; `action` is only a label. `start_time` (`HH:MM`, panel time) is used for `days` only. Chained schedules use `parent` plus `delay` seconds after the parent ran. Backup schedules carry `action_id` (backup config id, a string; leave the key out otherwise). An invalid cron string answers **405** with the message in `error`.

- **Files:** paths are relative to the server folder (absolute ones still work but are deprecated). A folder listing is an object keyed by name plus a `root_path` entry; `size` is the panel's own text (`"%3.1f"` + unit, so it may start with spaces), `modified` is `yyyy/MM/dd HH:mm` in panel time, `can_open` is the panel's guess for its editor (4.7.0 says `true` for `.gz`). Reading a non-UTF-8 file answers 400 `DECODE_ERROR` (4.11.0) or 500 (4.7.0); the app only opens known text types up to 1 MB. Saving sends the `modified_epoch` the file was read with: a newer file on disk answers **409** with an empty body unless `overwrite` is true, so the app asks before overwriting someone else's change. Creating an existing name answers 400 `FILE EXISTS`. Missing FILES permission answers 400 `NOT_AUTHORIZED`; traversal attempts 403 `TRAVERSAL DETECTED` (400 on 4.7.0).
- **Files on 4.7.0:** listing a folder that contains a name with `&`, `<`, `>`, `"` or `'` fails with **500** – the panel HTML-escapes the name and then cannot find the file. Fixed in 4.11.0. `files/copy` and `files/move` had a path traversal in 4.7.0 (issue #660); Kurafuto does not use them.
- **Panel permissions:** `permissions` is a bit string in `EnumPermissionsCrafty` order – server creation, user config, roles config. Superusers get `"000"`, so check `superuser` from `/users/@me` first. Adding is allowed when the bit is set and the counter is below the limit, or the limit is `-1`; a limit of `0` blocks adding (`can_add_in_crafty`). Per-server rights of the signed-in user are not exposed; the panel enforces them per request.
- **Missing panel rights** answer **400** `NOT_AUTHORIZED` (e.g. `GET /roles` without ROLES_CONFIG), not 403.
- **Invalid or expired token** (also after `invalidate_tokens`) answers **403** `ACCESS_DENIED`, not 401; `/metrics/*` does the same. **Wrong login data** answers **401** `INCORRECT_CREDENTIALS`. Disabled accounts get 403 `ACCOUNT_DISABLED`. Mapping in `APIClient.failure` (verified on 4.7.0 and 4.11.0).
- **Fresh tokens:** a token issued in the same second as the user's creation or a permission change is rejected as invalid; log in again a moment later.

More useful endpoints for later: `/api/v2/servers/{id}/users`, `/metrics/servers/{id}`, `/api/v2/crafty/config` (panel settings, superuser).

**Security:** never render MOTDs/logs as HTML (stored XSS in the web panel, issue #647). Never pass user-supplied
paths through unchecked (path traversal issue #660 affected files/copy|move in 4.7.0).
