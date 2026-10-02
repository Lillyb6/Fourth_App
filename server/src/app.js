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
    CREATE TABLE IF NOT EXISTS journal_entries (
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      date TEXT NOT NULL, kind TEXT NOT NULL CHECK (kind IN ('Note', 'Reminder', 'Journal')),
      body TEXT NOT NULL, created_at TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS journal_user_date ON journal_entries(user_id, date);
    CREATE TABLE IF NOT EXISTS check_ins (
      habit_id TEXT NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
      date TEXT NOT NULL, PRIMARY KEY (habit_id, date)
    );
  `);
  const app = express();
  app.disable('x-powered-by');
  app.use(helmet());
  // Allow only the fixed local Flutter web development origins.
  app.use((req, res, next) => {
    const origin = req.get('Origin');
    res.vary('Origin');
    if (['http://localhost:8080', 'http://127.0.0.1:8080'].includes(origin)) {
      res.set('Access-Control-Allow-Origin', origin);
      res.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
      res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
      if (req.method === 'OPTIONS') return res.sendStatus(204);
    }
    next();
  });
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

  function journalDate(value) {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) fail(400, 'Choose a valid date.');
    const date = new Date(`${value}T00:00:00Z`);
    if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 10) !== value) fail(400, 'Choose a valid date.');
    return value;
  }
  function journalInput(body) {
    const date = journalDate(body.date);
    if (!['Note', 'Reminder', 'Journal'].includes(body.kind)) fail(400, 'Choose Note, Reminder, or Journal.');
    return { date, kind: body.kind, body: string(body.body, 'Entry', 4000) };
  }
  function ownedEntry(req) {
    const entry = db.prepare('SELECT id, date, kind, body FROM journal_entries WHERE id = ? AND user_id = ?').get(req.params.id, req.user.id);
    if (!entry) fail(404, 'Entry not found.');
    return entry;
  }
  app.get('/api/journal', (req, res) => {
    const date = journalDate(req.query.date);
    res.json({ entries: db.prepare('SELECT id, date, kind, body FROM journal_entries WHERE user_id = ? AND date = ? ORDER BY created_at, id').all(req.user.id, date) });
  });
  app.post('/api/journal', (req, res) => {
    const input = journalInput(req.body ?? {});
    const id = randomUUID();
    db.prepare('INSERT INTO journal_entries VALUES (?, ?, ?, ?, ?, ?)').run(id, req.user.id, input.date, input.kind, input.body, new Date().toISOString());
    res.status(201).json({ entry: { id, ...input } });
  });
  app.put('/api/journal/:id', (req, res) => {
    const entry = ownedEntry(req);
    const input = journalInput(req.body ?? {});
    db.prepare('UPDATE journal_entries SET date = ?, kind = ?, body = ? WHERE id = ? AND user_id = ?').run(input.date, input.kind, input.body, entry.id, req.user.id);
    res.json({ entry: { id: entry.id, ...input } });
  });
  app.delete('/api/journal/:id', (req, res) => {
    const entry = ownedEntry(req);
    db.prepare('DELETE FROM journal_entries WHERE id = ? AND user_id = ?').run(entry.id, req.user.id);
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
