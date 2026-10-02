# Berry Daily

Flutter habit tracker with an Express REST API and SQLite storage.

## Run the connected Android app

Start the backend in a terminal and keep it running:

```powershell
cd server
npm.cmd ci
npm.cmd start
```

From the repository root in another terminal, start an Android emulator, then:

```powershell
flutter pub get
flutter run
```

The Android emulator connects to the computer at `http://10.0.2.2:3000`.
Sign up with an email and a password of 12–128 characters. Create habits,
check in, undo a check-in, and use the refresh button to load current data.
Habit history is loaded from the API. The logout button revokes the session.

Habits and accounts persist in `server/data/habitapp.sqlite`. Keep this file
when restarting the server. Login tokens stay in app memory for now: after a
full app restart, sign in again to retrieve your saved habits. Passwords and
tokens are not written to Flutter preferences or source files.

## Server address

Override the API URL when running against another server:

```powershell
flutter run --dart-define=API_BASE_URL=https://your-api.example.com
```

Windows development defaults to `http://127.0.0.1:3000`. Android debug builds
permit local HTTP only for `10.0.2.2`, `127.0.0.1`, and `localhost`.
For an Android phone connected over USB, forward its local port:

```powershell
adb reverse tcp:3000 tcp:3000
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

Release builds require an explicit HTTPS API URL. Local Flutter web is supported on port 8080; see below.
iOS/macOS local networking has not been configured or verified in this milestone.

## Verification

```powershell
flutter analyze
flutter test
flutter test test/api_live_test.dart --dart-define=RUN_LIVE_API_TEST=true
cd server
npm.cmd test
```

The live test requires Node.js 24+ and `npm.cmd ci` in `server`. It launches
an isolated API on an ephemeral local port and removes its temporary database.
It verifies registration, habit creation, check-in, logout/login, persistent
history, and undo through the actual Flutter HTTP client.

API and widget tests cover failed writes, session expiry, retry, and navigation.
Errors remain visible for retry; failed check-ins do not change local completion.
Accounts and habit data are removed from the navigation stack on logout or
expired sessions. The Accountability tab can create groups with an editable
generated invite code and submit join requests for owner approval. It lists groups
with member counts and an owner crown. Tap a group to view its details; owners
can view the invite code and approve or reject requests, with confirmation for
both actions. The list and details refresh every 10 seconds while visible and
the app is active. Owners see an action-needed badge for pending requests.
After ownership transfers, a new-owner notice remains until the new owner opens
the group; that acknowledgment is saved across sessions and devices.
Group details also include a confirmed Leave group action. Habit details include
Manage sharing: select groups, independently share description/schedule/history,
or make the habit private in all groups. Changes save immediately.
Group details show an expandable overall progress bar: the rounded average of
member percentages, excluding members with no habits scheduled for the app's
current local date. Expand it for member emails, percentages, and individual bars.
Shared habits appear under the person sharing them, with only the enabled details.
Check-in history is collapsed until tapped. These sections refresh automatically
with the rest of group details.

See [server/README.md](server/README.md) for endpoint details.

## Run in Chrome

Keep the backend running, then from the repository root run:

```powershell
flutter run -d chrome --web-hostname=127.0.0.1 --web-port=8080 --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

The backend permits browser requests from `http://127.0.0.1:8080` and
`http://localhost:8080`. Restart the backend after changing its code.

## Berry Daily tabs

- Dashboard: create habits and check them off for today.
- Progress: browse months and select a day to see saved habit completions.
- Journal: choose a date and add, edit, or delete private notes, reminders, and journal entries. Reminders are written entries, without scheduled notifications.
- Accountability: create and join groups, approve join requests, view group progress, and manage per-group habit sharing.

Journal entries persist in the same SQLite database as habits and accounts.
