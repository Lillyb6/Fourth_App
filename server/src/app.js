import express from 'express';
import helmet from 'helmet';
import { rateLimit } from 'express-rate-limit';
import { DatabaseSync } from 'node:sqlite';
import { randomBytes, randomUUID, scrypt, timingSafeEqual, createHash } from 'node:crypto';
import { promisify } from 'node:util';

const deriveKey = promisify(scrypt);
const digest = value => createHash('sha256').update(value).digest('hex');
const fail = (status, message) => { throw Object.assign(new Error(message), { status }); };

function string(value, field, max, optional = false) {
  if (optional && value === undefined) return '';
  if (typeof value !== 'string' || (!optional && !value.trim()) || value.length > max) {
    fail(400, `${field} must be ${optional ? 'at most' : 'between 1 and'} ${max} characters.`);
  }
  return value.trim();
}

function habitInput(body) {
  const name = string(body.name, 'name', 60);
  const description = string(body.description, 'description', 300, true);
  const schedule = body.schedule ?? 'daily';
  if (!['daily', 'weekdays'].includes(schedule)) fail(400, 'schedule must be daily or weekdays.');
  return { name, description, schedule };
}

function checkDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) fail(400, 'date must be YYYY-MM-DD.');
  const date = new Date(`${value}T00:00:00Z`);
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== value) {
    fail(400, 'date must be a real calendar date.');
  }
  // The client supplies its local calendar date, so allow the UTC+14 boundary.
  if (date.getTime() > Date.now() + 14 * 60 * 60 * 1000) fail(400, 'Future check-ins are not allowed.');
  return date;
}

export function createApp({ databasePath = ':memory:', sessionSeconds = 604800 } = {}) {
  const db = new DatabaseSync(databasePath);
  db.exec(`
    PRAGMA foreign_keys = ON;
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL, salt TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS sessions (
      token_hash TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      expires_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS habits (
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      name TEXT NOT NULL, description TEXT NOT NULL,
      schedule TEXT NOT NULL CHECK (schedule IN ('daily', 'weekdays')),
      created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS habits_user ON habits(user_id);
    CREATE TABLE IF NOT EXISTS check_ins (
      habit_id TEXT NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
      date TEXT NOT NULL, PRIMARY KEY (habit_id, date)
    );
    CREATE TABLE IF NOT EXISTS groups (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
      invite_code TEXT NOT NULL UNIQUE,
      created_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS group_memberships (
      group_id TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      joined_at TEXT NOT NULL,
      PRIMARY KEY (group_id, user_id)
    );
    CREATE INDEX IF NOT EXISTS group_memberships_user ON group_memberships(user_id);
    CREATE TABLE IF NOT EXISTS group_owner_notices (
      group_id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      FOREIGN KEY (group_id, user_id) REFERENCES group_memberships(group_id, user_id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS group_join_requests (
      group_id TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      requested_at TEXT NOT NULL,
      PRIMARY KEY (group_id, user_id)
    );
    CREATE TABLE IF NOT EXISTS habit_shares (
      habit_id TEXT NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
      group_id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      share_description INTEGER NOT NULL DEFAULT 0 CHECK (share_description IN (0, 1)),
      share_schedule INTEGER NOT NULL DEFAULT 0 CHECK (share_schedule IN (0, 1)),
      share_check_ins INTEGER NOT NULL DEFAULT 0 CHECK (share_check_ins IN (0, 1)),
      PRIMARY KEY (habit_id, group_id),
      FOREIGN KEY (group_id, user_id) REFERENCES group_memberships(group_id, user_id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS habit_shares_group ON habit_shares(group_id, user_id);
  `);
  const app = express();
  app.disable('x-powered-by');
  app.use(helmet());
  app.use(express.json({ limit: '16kb' }));
  app.use((req, res, next) => { res.set('Cache-Control', 'no-store'); next(); });
  app.get('/health', (req, res) => res.json({ status: 'ok' }));
  app.use('/api', rateLimit({ windowMs: 60000, limit: 120, standardHeaders: 'draft-8', legacyHeaders: false }));
  const authLimit = rateLimit({ windowMs: 900000, limit: 20, standardHeaders: 'draft-8', legacyHeaders: false });

  function session(userId) {
    const token = randomBytes(32).toString('base64url');
    const expiresAt = Date.now() + sessionSeconds * 1000;
    db.prepare('DELETE FROM sessions WHERE expires_at <= ?').run(Date.now());
    db.prepare('INSERT INTO sessions VALUES (?, ?, ?)').run(digest(token), userId, expiresAt);
    return { token, expiresAt: new Date(expiresAt).toISOString() };
  }

  function credentials(body) {
    const email = string(body.email, 'email', 254).toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) fail(400, 'Enter a valid email address.');
    const password = body.password;
    if (typeof password !== 'string' || password.length < 12 || password.length > 128) {
      fail(400, 'Password must be between 12 and 128 characters.');
    }
    return { email, password };
  }

  app.post('/api/auth/register', authLimit, async (req, res) => {
    const { email, password } = credentials(req.body ?? {});
    const salt = randomBytes(16).toString('hex');
    const hash = (await deriveKey(password, salt, 64)).toString('hex');
    const id = randomUUID();
    try {
      db.prepare('INSERT INTO users VALUES (?, ?, ?, ?)').run(id, email, hash, salt);
    } catch (error) {
      if (error.code === 'ERR_SQLITE_ERROR' && error.message.includes('UNIQUE constraint failed')) {
        fail(409, 'An account already exists for this email.');
      }
      throw error;
    }
    res.status(201).json({ user: { id, email }, ...session(id) });
  });
  app.post('/api/auth/login', authLimit, async (req, res) => {
    const { email, password } = credentials(req.body ?? {});
    const user = db.prepare('SELECT * FROM users WHERE email = ?').get(email);
    const hash = await deriveKey(password, user?.salt ?? '00000000000000000000000000000000', 64);
    const expected = user ? Buffer.from(user.password_hash, 'hex') : Buffer.alloc(64);
    if (!timingSafeEqual(hash, expected) || !user) fail(401, 'Incorrect email or password.');
    res.json({ user: { id: user.id, email: user.email }, ...session(user.id) });
  });

  app.use('/api', (req, res, next) => {
    const token = req.get('authorization')?.match(/^Bearer ([A-Za-z0-9_-]{43})$/)?.[1];
    if (!token) return next(Object.assign(new Error('Sign in to continue.'), { status: 401 }));
    const record = db.prepare(`SELECT users.id, users.email FROM sessions
      JOIN users ON users.id = sessions.user_id WHERE token_hash = ? AND expires_at > ?`)
      .get(digest(token), Date.now());
    if (!record) return next(Object.assign(new Error('Session expired or invalid.'), { status: 401 }));
    req.user = record;
    req.tokenHash = digest(token);
    next();
  });
  app.get('/api/auth/me', (req, res) => res.json({ user: req.user }));
  app.post('/api/auth/logout', (req, res) => {
    db.prepare('DELETE FROM sessions WHERE token_hash = ?').run(req.tokenHash);
    res.sendStatus(204);
  });

  app.post('/api/groups', (req, res) => {
    const name = string(req.body?.name, 'name', 60);
    let inviteCode = string(req.body?.inviteCode, 'inviteCode', 15, true).toUpperCase();
    if (inviteCode && !/^[A-Z0-9]{6,15}$/.test(inviteCode)) {
      fail(400, 'Invite code must contain 6–15 letters or numbers.');
    }
    const codeExists = code => db.prepare('SELECT id FROM groups WHERE UPPER(invite_code) = ?').get(code);
    if (inviteCode && codeExists(inviteCode)) {
      fail(409, 'Invite code already taken—choose another.');
    }
    if (!inviteCode) {
      do {
        inviteCode = randomBytes(4).toString('hex').toUpperCase();
      } while (codeExists(inviteCode));
    }
    const group = { id: randomUUID(), name, ownerId: req.user.id, inviteCode, createdAt: new Date().toISOString() };
    // Save both records together so every new group has its creator as a member.
    db.exec('BEGIN');
    try {
      db.prepare('INSERT INTO groups (id, name, owner_id, invite_code, created_at) VALUES (?, ?, ?, ?, ?)')
        .run(group.id, group.name, group.ownerId, group.inviteCode, group.createdAt);
      db.prepare('INSERT INTO group_memberships (group_id, user_id, joined_at) VALUES (?, ?, ?)')
        .run(group.id, group.ownerId, group.createdAt);
      db.exec('COMMIT');
    } catch (error) {
      db.exec('ROLLBACK');
      throw error;
    }
    res.status(201).json({ group });
  });

  app.post('/api/groups/join', (req, res) => {
    const inviteCode = string(req.body?.inviteCode, 'inviteCode', 15).toUpperCase();
    if (!/^[A-Z0-9]{6,15}$/.test(inviteCode)) {
      fail(400, 'Invite code must contain 6–15 letters or numbers.');
    }
    const group = db.prepare('SELECT * FROM groups WHERE UPPER(invite_code) = ?').get(inviteCode);
    if (!group) fail(404, 'No group found with that invite code.');
    if (db.prepare('SELECT 1 FROM group_memberships WHERE group_id = ? AND user_id = ?').get(group.id, req.user.id)) {
      fail(409, 'You’re already a member.');
    }
    const result = db.prepare('INSERT OR IGNORE INTO group_join_requests (group_id, user_id, requested_at) VALUES (?, ?, ?)')
      .run(group.id, req.user.id, new Date().toISOString());
    res.status(result.changes ? 202 : 200).json({ status: 'pending', message: 'Your request is pending approval.' });
  });

  app.get('/api/groups', (req, res) => {
    const groups = db.prepare(`SELECT groups.*,
      (SELECT COUNT(*) FROM group_memberships WHERE group_id = groups.id) AS member_count,
      (SELECT COUNT(*) FROM group_join_requests WHERE group_id = groups.id) AS pending_count,
      EXISTS(SELECT 1 FROM group_owner_notices WHERE group_id = groups.id AND user_id = groups.owner_id) AS owner_notice
      FROM groups JOIN group_memberships ON group_memberships.group_id = groups.id
      WHERE group_memberships.user_id = ? ORDER BY groups.created_at, groups.id`).all(req.user.id);
    res.json({ groups: groups.map(group => ({
      id: group.id, name: group.name, memberCount: group.member_count,
      isOwner: group.owner_id === req.user.id,
      ...(group.owner_id === req.user.id ? {
        inviteCode: group.invite_code,
        pendingRequestCount: group.pending_count,
        ownershipChanged: Boolean(group.owner_notice),
      } : {}),
    })) });
  });

  app.get('/api/groups/:id/progress', (req, res) => {
    const membership = db.prepare('SELECT 1 FROM group_memberships WHERE group_id = ? AND user_id = ?')
      .get(req.params.id, req.user.id);
    if (!membership) fail(404, 'Group not found.');
    const date = string(req.query.date, 'date', 10);
    const isWeekday = ![0, 6].includes(checkDate(date).getUTCDay());
    const members = db.prepare(`SELECT users.id, users.email,
      COUNT(habits.id) AS scheduled, COUNT(check_ins.habit_id) AS completed
      FROM group_memberships JOIN users ON users.id = group_memberships.user_id
      LEFT JOIN habits ON habits.user_id = users.id AND (habits.schedule = 'daily' OR ?)
      LEFT JOIN check_ins ON check_ins.habit_id = habits.id AND check_ins.date = ?
      WHERE group_memberships.group_id = ?
      GROUP BY users.id, users.email ORDER BY users.email, users.id`)
      .all(isWeekday ? 1 : 0, date, req.params.id);
    res.json({ date, members: members.map(member => ({
      userId: member.id,
      email: member.email,
      completionPercentage: member.scheduled ? Math.round(member.completed / member.scheduled * 100) : null,
      ...(member.scheduled ? {} : { message: 'No habits scheduled' }),
    })) });
  });

  function ownedGroup(req) {
    const group = db.prepare('SELECT * FROM groups WHERE id = ? AND owner_id = ?').get(req.params.id, req.user.id);
    if (!group) fail(404, 'Group not found.');
    return group;
  }
  app.delete('/api/groups/:id/owner-notice', (req, res) => {
    const group = ownedGroup(req);
    db.prepare('DELETE FROM group_owner_notices WHERE group_id = ? AND user_id = ?').run(group.id, req.user.id);
    res.sendStatus(204);
  });
  app.get('/api/groups/:id/shared-habits', (req, res) => {
    if (!db.prepare('SELECT 1 FROM group_memberships WHERE group_id = ? AND user_id = ?').get(req.params.id, req.user.id)) {
      fail(404, 'Group not found.');
    }
    const shares = db.prepare(`SELECT habits.id, habits.name, habits.description, habits.schedule,
      users.id AS user_id, users.email, share_description, share_schedule, share_check_ins
      FROM habit_shares JOIN habits ON habits.id = habit_shares.habit_id AND habits.user_id = habit_shares.user_id
      JOIN users ON users.id = habit_shares.user_id
      WHERE habit_shares.group_id = ? ORDER BY users.email, habits.name, habits.id`).all(req.params.id);
    res.json({ habits: shares.map(share => ({
      id: share.id, userId: share.user_id, email: share.email, name: share.name,
      ...(share.share_description ? { description: share.description } : {}),
      ...(share.share_schedule ? { schedule: share.schedule } : {}),
      ...(share.share_check_ins ? { checkIns: db.prepare('SELECT date FROM check_ins WHERE habit_id = ? ORDER BY date DESC')
        .all(share.id).map(row => row.date) } : {}),
    })) });
  });
  app.get('/api/groups/:id/requests', (req, res) => {
    const group = ownedGroup(req);
    const requests = db.prepare(`SELECT users.id AS userId, users.email, requested_at AS requestedAt
      FROM group_join_requests JOIN users ON users.id = group_join_requests.user_id
      WHERE group_id = ? ORDER BY requested_at, users.id`).all(group.id);
    res.json({ requests });
  });
  app.post('/api/groups/:id/requests/:userId/approve', (req, res) => {
    db.exec('BEGIN');
    try {
      const group = ownedGroup(req);
      const request = db.prepare('SELECT 1 FROM group_join_requests WHERE group_id = ? AND user_id = ?')
        .get(group.id, req.params.userId);
      if (!request) fail(404, 'Join request not found.');
      db.prepare('INSERT INTO group_memberships (group_id, user_id, joined_at) VALUES (?, ?, ?)')
        .run(group.id, req.params.userId, new Date().toISOString());
      db.prepare('DELETE FROM group_join_requests WHERE group_id = ? AND user_id = ?').run(group.id, req.params.userId);
      db.exec('COMMIT');
    } catch (error) {
      db.exec('ROLLBACK');
      throw error;
    }
    res.sendStatus(204);
  });
  app.delete('/api/groups/:id/requests/:userId', (req, res) => {
    const group = ownedGroup(req);
    const result = db.prepare('DELETE FROM group_join_requests WHERE group_id = ? AND user_id = ?')
      .run(group.id, req.params.userId);
    if (!result.changes) fail(404, 'Join request not found.');
    res.sendStatus(204);
  });

  app.delete('/api/groups/:id/membership', (req, res) => {
    db.exec('BEGIN');
    try {
      const group = db.prepare(`SELECT groups.* FROM groups
        JOIN group_memberships ON group_memberships.group_id = groups.id
        WHERE groups.id = ? AND group_memberships.user_id = ?`).get(req.params.id, req.user.id);
      if (!group) fail(404, 'Group not found.');
      if (group.owner_id === req.user.id) {
        const nextOwner = db.prepare(`SELECT user_id FROM group_memberships
          WHERE group_id = ? AND user_id != ? ORDER BY joined_at, rowid LIMIT 1`)
          .get(group.id, req.user.id);
        if (nextOwner) {
          db.prepare('UPDATE groups SET owner_id = ? WHERE id = ?').run(nextOwner.user_id, group.id);
          db.prepare(`INSERT INTO group_owner_notices (group_id, user_id) VALUES (?, ?)
            ON CONFLICT (group_id) DO UPDATE SET user_id = excluded.user_id`).run(group.id, nextOwner.user_id);
        } else {
          db.prepare('DELETE FROM groups WHERE id = ?').run(group.id);
        }
      }
      db.prepare('DELETE FROM group_memberships WHERE group_id = ? AND user_id = ?')
        .run(group.id, req.user.id);
      db.exec('COMMIT');
    } catch (error) {
      db.exec('ROLLBACK');
      throw error;
    }
    res.sendStatus(204);
  });

  function ownedHabit(req) {
    const habit = db.prepare('SELECT * FROM habits WHERE id = ? AND user_id = ?').get(req.params.id, req.user.id);
    if (!habit) fail(404, 'Habit not found.');
    return habit;
  }
  function serialize(habit) {
    return {
      id: habit.id, name: habit.name, description: habit.description, schedule: habit.schedule,
      createdAt: habit.created_at,
      checkIns: db.prepare('SELECT date FROM check_ins WHERE habit_id = ? ORDER BY date DESC').all(habit.id).map(row => row.date),
    };
  }
  app.get('/api/habits/:id/shares', (req, res) => {
    const habit = ownedHabit(req);
    const shares = db.prepare('SELECT * FROM habit_shares WHERE habit_id = ? ORDER BY group_id').all(habit.id);
    res.json({ shares: shares.map(share => ({
      groupId: share.group_id,
      shareDescription: Boolean(share.share_description),
      shareSchedule: Boolean(share.share_schedule),
      shareCheckIns: Boolean(share.share_check_ins),
    })) });
  });
  app.put('/api/habits/:id/shares/:groupId', (req, res) => {
    const habit = ownedHabit(req);
    if (!db.prepare('SELECT 1 FROM group_memberships WHERE group_id = ? AND user_id = ?').get(req.params.groupId, req.user.id)) {
      fail(404, 'Group not found.');
    }
    const options = {};
    for (const field of ['shareDescription', 'shareSchedule', 'shareCheckIns']) {
      const value = req.body?.[field];
      if (value !== undefined && typeof value !== 'boolean') fail(400, `${field} must be true or false.`);
      options[field] = value === true;
    }
    db.prepare(`INSERT INTO habit_shares (habit_id, group_id, user_id, share_description, share_schedule, share_check_ins)
      VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT (habit_id, group_id) DO UPDATE SET
      share_description = excluded.share_description, share_schedule = excluded.share_schedule,
      share_check_ins = excluded.share_check_ins`)
      .run(habit.id, req.params.groupId, req.user.id, Number(options.shareDescription), Number(options.shareSchedule), Number(options.shareCheckIns));
    res.json({ share: { groupId: req.params.groupId, ...options } });
  });
  app.delete('/api/habits/:id/shares', (req, res) => {
    const habit = ownedHabit(req);
    db.prepare('DELETE FROM habit_shares WHERE habit_id = ?').run(habit.id);
    res.sendStatus(204);
  });
  app.delete('/api/habits/:id/shares/:groupId', (req, res) => {
    const habit = ownedHabit(req);
    db.prepare('DELETE FROM habit_shares WHERE habit_id = ? AND group_id = ?').run(habit.id, req.params.groupId);
    res.sendStatus(204);
  });
  app.get('/api/habits', (req, res) => {
    const habits = db.prepare('SELECT * FROM habits WHERE user_id = ? ORDER BY created_at, id').all(req.user.id);
    res.json({ habits: habits.map(serialize) });
  });
  app.post('/api/habits', (req, res) => {
    const input = habitInput(req.body ?? {});
    const id = randomUUID();
    db.prepare('INSERT INTO habits VALUES (?, ?, ?, ?, ?, ?)')
      .run(id, req.user.id, input.name, input.description, input.schedule, new Date().toISOString());
    res.location(`/api/habits/${id}`).status(201).json({ habit: serialize(db.prepare('SELECT * FROM habits WHERE id = ?').get(id)) });
  });
  app.get('/api/habits/:id', (req, res) => res.json({ habit: serialize(ownedHabit(req)) }));
  app.put('/api/habits/:id', (req, res) => {
    const habit = ownedHabit(req);
    const input = habitInput(req.body ?? {});
    db.prepare('UPDATE habits SET name = ?, description = ?, schedule = ? WHERE id = ?')
      .run(input.name, input.description, input.schedule, habit.id);
    res.json({ habit: serialize(ownedHabit(req)) });
  });
  app.delete('/api/habits/:id', (req, res) => {
    const habit = ownedHabit(req);
    db.prepare('DELETE FROM habits WHERE id = ?').run(habit.id);
    res.sendStatus(204);
  });
  app.put('/api/habits/:id/check-ins/:date', (req, res) => {
    const habit = ownedHabit(req);
    const date = checkDate(req.params.date);
    if (habit.schedule === 'weekdays' && [0, 6].includes(date.getUTCDay())) fail(400, 'This habit is scheduled on weekdays only.');
    const result = db.prepare('INSERT OR IGNORE INTO check_ins VALUES (?, ?)').run(habit.id, req.params.date);
    res.status(result.changes ? 201 : 200).json({ habit: serialize(habit) });
  });
  app.delete('/api/habits/:id/check-ins/:date', (req, res) => {
    const habit = ownedHabit(req);
    checkDate(req.params.date);
    db.prepare('DELETE FROM check_ins WHERE habit_id = ? AND date = ?').run(habit.id, req.params.date);
    res.sendStatus(204);
  });
  app.use((req, res) => res.status(404).json({ error: 'Endpoint not found.' }));
  app.use((error, req, res, next) => {
    const status = error.status >= 400 && error.status < 500 ? error.status : 500;
    if (status === 500) console.error(error);
    res.status(status).json({ error: status === 500 ? 'Internal server error.' : error.type === 'entity.parse.failed' ? 'Invalid JSON body.' : error.message });
  });
  return { app, close: () => db.close() };
}
