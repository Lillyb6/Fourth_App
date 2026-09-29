import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createApp } from '../src/app.js';

async function fixture(options = {}) {
  const { app, close } = createApp(options);
  const server = app.listen(0, '127.0.0.1');
  await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  return {
    async request(path, { method = 'GET', body, token } = {}) {
      const response = await fetch(base + path, { method,
        headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
        body: body === undefined ? undefined : JSON.stringify(body),
      });
      return { status: response.status, data: response.status === 204 ? null : await response.json() };
    },
    async close() { await new Promise(resolve => server.close(resolve)); close(); },
  };
}
const account = email => ({ email, password: 'a-long-test-password' });

test('accounts, private habits, validation, check-in deduplication, undo and logout', async t => {
  const f = await fixture(); t.after(() => f.close());
  const call = f.request;
  assert.equal((await call('/health')).status, 200);
  assert.equal((await call('/api/habits')).status, 401);
  const alice = await call('/api/auth/register', { method: 'POST', body: account('alice@example.com') });
  assert.equal(alice.status, 201);
  assert.equal((await call('/api/auth/register', { method: 'POST', body: account('alice@example.com') })).status, 409);
  assert.equal((await call('/api/auth/login', { method: 'POST', body: { ...account('alice@example.com'), password: 'wrong-long-password' } })).status, 401);
  const token = alice.data.token;
  const bob = await call('/api/auth/register', { method: 'POST', body: account('bob@example.com') });
  assert.equal((await call('/api/habits', { method: 'POST', token, body: { name: ' ' } })).status, 400);
  const created = await call('/api/habits', { method: 'POST', token, body: { name: 'Read', schedule: 'weekdays' } });
  assert.equal(created.status, 201);
  const path = `/api/habits/${created.data.habit.id}`;
  assert.deepEqual((await call('/api/habits', { token: bob.data.token })).data.habits, []);
  for (const method of ['GET', 'PUT', 'DELETE']) {
    assert.equal((await call(path, { method, token: bob.data.token, ...(method === 'PUT' ? { body: { name: 'Stolen' } } : {}) })).status, 404);
  }
  assert.equal((await call(`${path}/check-ins/2026-01-05`, { method: 'PUT', token: bob.data.token })).status, 404);
  assert.equal((await call(`${path}/check-ins/2026-02-30`, { method: 'PUT', token })).status, 400);
  assert.equal((await call(`${path}/check-ins/2099-01-01`, { method: 'PUT', token })).status, 400);
  assert.equal((await call(`${path}/check-ins/2026-01-04`, { method: 'PUT', token })).status, 400);
  assert.equal((await call(`${path}/check-ins/2026-01-05`, { method: 'PUT', token })).status, 201);
  assert.equal((await call(`${path}/check-ins/2026-01-05`, { method: 'PUT', token })).status, 200);
  assert.deepEqual((await call(path, { token })).data.habit.checkIns, ['2026-01-05']);
  assert.equal((await call(`${path}/check-ins/2026-01-05`, { method: 'DELETE', token })).status, 204);
  assert.deepEqual((await call(path, { token })).data.habit.checkIns, []);
  assert.equal((await call(path, { method: 'PUT', token, body: { name: 'Read a chapter', schedule: 'daily' } })).data.habit.name, 'Read a chapter');
  assert.equal((await call(path, { method: 'DELETE', token })).status, 204);
  assert.equal((await call(path, { token })).status, 404);
  assert.equal((await call('/api/auth/logout', { method: 'POST', token })).status, 204);
  assert.equal((await call('/api/auth/me', { token })).status, 401);
});

test('SQLite retains accounts, habits and check-ins across server restarts', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'habitapp-test-'));
  let f;
  try {
    f = await fixture({ databasePath: join(dir, 'test.sqlite') });
    const registered = await f.request('/api/auth/register', { method: 'POST', body: account('persist@example.com') });
    const token = registered.data.token;
    const created = await f.request('/api/habits', { method: 'POST', token, body: { name: 'Persist me' } });
    await f.request(`/api/habits/${created.data.habit.id}/check-ins/2026-01-05`, { method: 'PUT', token });
    await f.close(); f = null;
    f = await fixture({ databasePath: join(dir, 'test.sqlite') });
    const login = await f.request('/api/auth/login', { method: 'POST', body: account('persist@example.com') });
    assert.equal(login.status, 200);
    const saved = (await f.request('/api/habits', { token: login.data.token })).data.habits;
    assert.equal(saved[0].name, 'Persist me');
    assert.deepEqual(saved[0].checkIns, ['2026-01-05']);
  } finally { if (f) await f.close(); rmSync(dir, { recursive: true, force: true }); }
});

test('expired sessions cannot read habits', async t => {
  const f = await fixture({ sessionSeconds: -1 }); t.after(() => f.close());
  const user = await f.request('/api/auth/register', { method: 'POST', body: account('expired@example.com') });
  assert.equal((await f.request('/api/habits', { token: user.data.token })).status, 401);
});
