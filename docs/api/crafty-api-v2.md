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
| send(action) | `POST /api/v2/servers/{id}/action/{start_server…}[/{action_id}]` | ✅ | start, stop, restart, kill ✅ · backup see below · clone, update – |
| acceptEULA | `POST /api/v2/servers/{id}/action/eula` (writes `eula.txt`, then starts the server) | ⚠️ action name from panel source | ✅ |
| sendCommand | `POST /api/v2/servers/{id}/stdin` (text/plain, no leading /) | ✅ | ✅ |
| logs | `GET /api/v2/servers/{id}/logs?file=&colors=&raw=&html=` | ✅ | ✅ live buffer and file |
| stats | `GET /api/v2/servers/{id}/stats` | ✅ | ✅ stopped and running |
| schedules | `GET /api/v2/servers/{id}/tasks` | ⚠️ not in spec | – |
| create/update/deleteSchedule | `POST …/tasks`, `PATCH/DELETE …/tasks/{taskID}` | ✅ | – |
| webhooks | `GET /api/v2/servers/{id}/webhook` | ✅ | – |
| saveWebhook | `POST /api/v2/servers/{id}/webhook` · `PATCH /api/v2/server/{id}/webhook/{wid}` | ✅ (note singular "server") | – |
| panelAccess | `GET /api/v2/users/@me` (superuser) + `GET /api/v2/users/@me/permissions` | ✅ | ✅ superuser, no rights, mask `101` |
| users / saveUser / deleteUser | `/api/v2/users`, `/api/v2/users/{id}` | ✅ | – |
| roles / saveRole / deleteRole | `/api/v2/roles`, `/api/v2/roles/{id}` | ✅ | – |
| hostStats | `GET /metrics/host` (OpenMetrics text) | ✅ | – |
| announcements / clear | `GET/POST /api/v2/crafty/announcements` | ✅ | – |
| backupConfigs, backupFiles, restore, delete | `/api/v2/servers/{id}/backups/…` | ⚠️ | – |
| listFiles, readFile, writeFile, createFolder, deleteFile | `/api/v2/servers/{id}/files/…` (since 4.7 incl. copy/move) | ⚠️ | – |
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
- **Backup:** `action/backup_server` without an id uses the default backup config on 4.11.0. On 4.7.0 it answers `ok` but the backup fails inside the panel (`BackupsDoesNotExist`); it needs `action/backup_server/{backup_id}`. To be fixed together with the backups item in 0.3.

- **Panel permissions:** `permissions` is a bit string in `EnumPermissionsCrafty` order – server creation, user config, roles config. Superusers get `"000"`, so check `superuser` from `/users/@me` first. Adding is allowed when the bit is set and the counter is below the limit, or the limit is `-1`; a limit of `0` blocks adding (`can_add_in_crafty`). Per-server rights of the signed-in user are not exposed; the panel enforces them per request.
- **Missing panel rights** answer **400** `NOT_AUTHORIZED` (e.g. `GET /roles` without ROLES_CONFIG), not 403.
- **Fresh tokens:** a token issued in the same second as the user's creation or a permission change is rejected as invalid; log in again a moment later.

More useful endpoints for later: `/api/v2/servers/{id}/users`, `/metrics/servers/{id}`, `/api/v2/crafty/config` (panel settings, superuser).

**Security:** never render MOTDs/logs as HTML (stored XSS in the web panel, issue #647). Never pass user-supplied
paths through unchecked (path traversal issue #660 affected files/copy|move in 4.7.0).
