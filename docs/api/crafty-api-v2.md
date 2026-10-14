# Crafty API v2 → CraftyService

Based on `openapi-spec.yml` v2.0.1 (docs.craftycontrol.com). Auth: `Authorization: Bearer <token>`.
Responses: `{"status":"ok","data":…}` / `{"status":"error","error":"CODE","error_data":"…"}`.

| CraftyService | Method & path | Docs |
|---|---|---|
| login | `POST /api/v2/auth/login` {username,password,totp?} | ✅ |
| invalidateAllSessions | `POST /api/v2/auth/invalidate_tokens` | ✅ |
| healthCheck | `GET /api/v2/crafty/check` | ✅ |
| servers | `GET /api/v2/servers` | ✅ |
| server | `GET /api/v2/servers/{id}` | ✅ (example in spec is wrong) |
| createServer | `POST /api/v2/servers` | ✅ |
| updateServer | `PATCH /api/v2/servers/{id}` | ✅ |
| deleteServer | `DELETE /api/v2/servers/{id}` | ✅ |
| send(action) | `POST /api/v2/servers/{id}/action/{start_server…}` | ✅ |
| sendCommand | `POST /api/v2/servers/{id}/stdin` (text/plain, no leading /) | ✅ |
| logs | `GET /api/v2/servers/{id}/logs?file=&colors=&raw=&html=` | ✅ |
| stats | `GET /api/v2/servers/{id}/stats` | ✅ |
| schedules | `GET /api/v2/servers/{id}/tasks` | ⚠️ not in spec |
| create/update/deleteSchedule | `POST …/tasks`, `PATCH/DELETE …/tasks/{taskID}` | ✅ |
| webhooks | `GET /api/v2/servers/{id}/webhook` | ✅ |
| saveWebhook | `POST /api/v2/servers/{id}/webhook` · `PATCH /api/v2/server/{id}/webhook/{wid}` | ✅ (note singular "server") |
| users / saveUser / deleteUser | `/api/v2/users`, `/api/v2/users/{id}` | ✅ |
| roles / saveRole / deleteRole | `/api/v2/roles`, `/api/v2/roles/{id}` | ✅ |
| hostStats | `GET /metrics/host` (OpenMetrics text) | ✅ |
| announcements / clear | `GET/POST /api/v2/crafty/announcements` | ✅ |
| backupConfigs, backupFiles, restore, delete | `/api/v2/servers/{id}/backups/…` | ⚠️ |
| listFiles, readFile, writeFile, createFolder, deleteFile | `/api/v2/servers/{id}/files/…` (since 4.7 incl. copy/move) | ⚠️ |
| consoleStream | web panel WebSocket `/ws` | ⚠️ undocumented, polling as fallback |

More useful endpoints for later: `/api/v2/users/{id}/permissions` (hide UI based on permissions),
`/api/v2/servers/{id}/users`, `/metrics/servers/{id}`, `/api/v2/crafty/config` (panel settings, superuser).

**Security:** never render MOTDs/logs as HTML (stored XSS in the web panel, issue #647). Never pass user-supplied
paths through unchecked (path traversal issue #660 affected files/copy|move in 4.7.0).
