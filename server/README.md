# HabitApp REST API

The backend supports accounts, private habits, check-ins, groups, and optional habit sharing.
The Flutter screens are not connected yet. Streak calculations,
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
Flutter integration will need a development-only HTTP network policy and a
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
| POST | `/api/groups` | Create a group and add its owner as the first member |
| GET | `/api/groups` | List your approved groups with member counts and owner status |
| GET | `/api/groups/:id/progress?date=YYYY-MM-DD` | Members only: daily completion percentages |
| GET | `/api/groups/:id/shared-habits` | Members only: habits explicitly shared with this group |
| POST | `/api/groups/join` | Request to join using an invite code |
| GET | `/api/groups/:id/requests` | Owner only: list pending applicants |
| POST | `/api/groups/:id/requests/:userId/approve` | Owner only: approve an applicant |
| DELETE | `/api/groups/:id/requests/:userId` | Owner only: reject an applicant |
| DELETE | `/api/groups/:id/membership` | Leave a group as the signed-in user |
| GET | `/api/habits` | List your habits |
| POST | `/api/habits` | Create habit |
| GET | `/api/habits/:id` | Habit details and check-in history |
| PUT | `/api/habits/:id` | Replace editable habit fields |
| DELETE | `/api/habits/:id` | Delete habit and its check-ins |
| GET | `/api/habits/:id/shares` | Habit owner only: view sharing settings for each group |
| PUT | `/api/habits/:id/shares/:groupId` | Habit owner only: share or replace this group's sharing settings |
| DELETE | `/api/habits/:id/shares/:groupId` | Habit owner only: stop sharing with this group |
| PUT | `/api/habits/:id/check-ins/:date` | Check in, safely repeatable |
| DELETE | `/api/habits/:id/check-ins/:date` | Undo check-in, safely repeatable |

Group input: `{ "name": "Study Buddies", "inviteCode": "STUDY42" }`.
Name is required (1–60 characters). Invite code is optional; omit it or leave it
blank to generate an 8-character code. Custom codes accept 6–15 ASCII letters
or numbers and are stored uppercase. A taken code returns 409 with
`Invite code already taken—choose another.` Creation requires login and returns
201 with `{group: {id, name, ownerId, inviteCode, createdAt}}`. The signed-in user
is the owner; the group and its first membership are saved together.

Join input: `{ "inviteCode": "STUDY42" }`. Requires login; codes ignore capitalization.
Returns 202 with `{status: "pending", message: "Your request is pending approval."}`.
Repeating a pending request returns 200 with the same response. Invalid code formats
return 400, unknown codes return 404, and existing members (including the owner)
receive 409 with `You’re already a member.` Joining does not share private habits.

Group lists return `{groups: [{id, name, memberCount, isOwner}]}`. Only the owner
also receives `inviteCode`. Pending requests do not count as memberships or
appear in the applicant's group list. The frontend can use `isOwner` for a crown.
Owners can list `{requests: [{userId, email, requestedAt}]}` and approve or reject
each request. Both actions return 204; missing requests return 404. Nonowners
cannot read requests or make decisions (404). Rejected applicants can request again.
Approval creates the membership; join order for ownership succession starts then.
Existing memberships are preserved when this server version starts.

Leaving returns 204. If the owner leaves, ownership transfers to the earliest
remaining member by join date (membership insertion order breaks ties). If the
owner is alone, the group is deleted. Nonmembers and unknown groups return 404.
Leaving also removes that user's habit shares for the group, but keeps their habits
and account. Rejoining does not restore old shares; sharing must be enabled again.

Progress requires the app's local calendar date, using the same date convention
as check-ins. All members are evaluated for that date. It returns
`{date, members: [{userId, email, completionPercentage}]}` for approved members
only. Percentages are rounded to whole numbers and count daily habits plus
weekday habits on Monday–Friday. A member with no scheduled habits receives
`completionPercentage: null` and `message: "No habits scheduled"`.
Only current members can read progress; pending applicants, former members,
and outsiders receive 404. Responses contain no habit names, descriptions,
check-in history, or invite codes. Calculations use the current habit schedules;
this is not a historical snapshot of past schedule changes.

## Habit sharing

Habits are not shared by default. The habit owner must be an approved member of
each group they share with. Sharing with one group does not affect other groups.
Only the habit owner can read or change sharing settings, even if someone else
owns the group.

Send `PUT /api/habits/:id/shares/:groupId` with:

```json
{"shareDescription": false, "shareSchedule": false, "shareCheckIns": false}
```

All three options accept only booleans and default to false when omitted. Each
PUT replaces the options for that group, so send all current switch values when
saving. An empty object shares only the name. Returns 200 with
`{share: {groupId, shareDescription, shareSchedule, shareCheckIns}}`.
`GET /api/habits/:id/shares` returns `{shares: [...]}` with those same settings.
DELETE stops sharing with that group and returns 204, including repeated deletes.

Group members read `{habits: [{id, userId, email, name}]}` from the shared-habits
endpoint. Description, schedule, and checkIns are included only when their
respective options are enabled; disabled fields are omitted entirely. Check-in
sharing includes the full current history, newest first. Shared values reflect
later habit edits and check-ins. The owner's existing private habit endpoint
remains owner-only. Pending applicants, outsiders, and former members cannot
read shared habits. Deleting a habit or group also removes its sharing records.

## Habit requests

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
