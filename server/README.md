# HabitApp REST API

First backend milestone: accounts, private habits, and persistent daily check-ins.
The Flutter Android screens now connect to this API; see the root README. Groups, sharing, streak calculations,
email verification, and password reset are future milestones.

## Run locally

Requires Node.js 24 or later. From this folder:

```powershell
npm.cmd ci
npm.cmd test
npm.cmd start
```

The server listens on `http://127.0.0.1:3000`. Open `/health` to check it.
SQLite creates `server/data/habitapp.sqlite` automatically; keep this file to
retain accounts and habits. The data folder is excluded from Git.
`PORT`, `HOST`, and `DATABASE_PATH` environment variables override defaults.
The built-in Node SQLite API may print an experimental warning on Node 24.11.

For the Android emulator, the host computer is `http://10.0.2.2:3000`.
Android debug builds include a local-only HTTP network policy and a
configurable base URL. Flutter web will also need an explicit CORS allowlist.
This is a local development server; use HTTPS and a reviewed deployment setup
before exposing accounts over the internet.

## JSON endpoints

All protected endpoints require `Authorization: Bearer <token>`.
Register/login return `{user: {id, email}, token, expiresAt}`. Sessions expire
after seven days; logout revokes the current session. Passwords are hashed with
scrypt and random salts; only token hashes are stored in SQLite.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/health` | Health check |
| POST | `/api/auth/register` | Create account with email and password (12–128 characters) |
| POST | `/api/auth/login` | Sign in with email and password |
| GET | `/api/auth/me` | Current account |
| POST | `/api/auth/logout` | Revoke session |
| GET | `/api/habits` | List your habits |
| POST | `/api/habits` | Create habit |
| GET | `/api/habits/:id` | Habit details and check-in history |
| PUT | `/api/habits/:id` | Replace editable habit fields |
| DELETE | `/api/habits/:id` | Delete habit and its check-ins |
| PUT | `/api/habits/:id/check-ins/:date` | Check in, safely repeatable |
| DELETE | `/api/habits/:id/check-ins/:date` | Undo check-in, safely repeatable |

Habit input: `{ "name": "Read", "description": "One chapter", "schedule": "daily" }`.
`schedule` is `daily` or `weekdays` (Monday–Friday). Description is optional.
Create/update return `{habit: ...}`; list returns `{habits: [...]}`.
Habit objects include `id`, `name`, `description`, `schedule`, `createdAt`, and
`checkIns` (calendar-date strings, newest first).

Send check-in dates as `YYYY-MM-DD` in the user's local calendar. Backdated
entries are supported. Invalid dates, future dates beyond the UTC+14 boundary,
and weekend check-ins for weekday habits are rejected. Repeating a check-in
returns 200 instead of creating duplicates (first creation returns 201).
Changing a schedule preserves existing check-in history.

Authentication is required for every habit operation. Other users' habit IDs
return 404. Validation errors use 400; bad sessions use 401; duplicate accounts
use 409. Errors return `{error: "message"}` (rate limiting may return text).
Successful deletes and logout return 204 with no body.

## Try it in PowerShell

Use a test password; do not paste real credentials into shared terminal logs.

```powershell
$account = Invoke-RestMethod http://127.0.0.1:3000/api/auth/register -Method Post -ContentType 'application/json' -Body '{"email":"demo@example.com","password":"local-demo-password"}'
$headers = @{ Authorization = "Bearer $($account.token)" }
Invoke-RestMethod http://127.0.0.1:3000/api/habits -Method Post -Headers $headers -ContentType 'application/json' -Body '{"name":"Read a chapter","schedule":"daily"}'
Invoke-RestMethod http://127.0.0.1:3000/api/habits -Headers $headers
```

Tests cover ownership isolation, validation, weekday scheduling, duplicate
prevention, undo, deletion, login/logout, session expiry, and disk persistence.
