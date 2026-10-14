import { afterAll, beforeAll, beforeEach, describe, expect, test } from 'bun:test';
import { randomUUID } from 'node:crypto';
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import { eq } from 'drizzle-orm';
import { createApp } from '../index.ts';
import { migrateAuth } from '../auth-migration.ts';
import { tokenHash, validateAuthConfig, type AuthConfig, type GoogleProvider } from '../auth.ts';
import { authSessions, loginAttempts, users } from '../schema.ts';

const databaseUrl = process.env.TEST_DATABASE_URL;
if (!databaseUrl) throw new Error('Configura TEST_DATABASE_URL para ejecutar las pruebas de integración en PostgreSQL.');
// Everything, including migrations and cleanup, stays in a disposable schema.
const schemaName = `hevy_auth_test_${randomUUID().replaceAll('-', '')}`;
const admin = postgres(databaseUrl, { max: 1, onnotice: () => {} });
const client = postgres(databaseUrl, { max: 5, connection: { search_path: schemaName }, onnotice: () => {} });
const db = drizzle(client);
const legacyId = '00000000-0000-4000-8000-000000000001';
const config: AuthConfig = {
  clientId: 'test-client', clientSecret: 'test-secret',
  webOrigin: 'https://app.i7l.cl', redirectUri: 'https://app.i7l.cl/api/auth/google/callback',
};
let exchangeCalls = 0;
const provider: GoogleProvider = {
  authorizationUrl: (state, nonce, challenge) => `https://accounts.google.com/test?state=${state}&nonce=${nonce}&code_challenge=${challenge}`,
  async exchange(code, verifier, nonce) {
    exchangeCalls++;
    const [attempt] = await db.select().from(loginAttempts).where(eq(loginAttempts.nonce, nonce));
    if (!attempt || attempt.verifier !== verifier || code === 'denied') throw new Error('Invalid identity');
    return { subject: `google-${code}`, email: `${code}@example.com` };
  },
};
let app: ReturnType<typeof createApp>;
const request = (path: string, method = 'GET', body?: unknown, headers: Record<string, string> = {}) =>
  app.handle(new Request(`http://localhost${path}`, {
    method, headers: { ...(body === undefined ? {} : { 'content-type': 'application/json' }), ...headers },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }));

async function start(web = false) {
  const response = await request(`/auth/google/start${web ? '?web=1' : ''}`, 'POST');
  expect(response.status).toBe(200);
  const data = await response.json() as { attemptToken?: string; authorizationUrl: string };
  const state = new URL(data.authorizationUrl).searchParams.get('state')!;
  return { ...data, state, cookie: response.headers.get('set-cookie')?.split(';')[0] ?? '' };
}
async function login(code: string) {
  const attempt = await start();
  expect((await request(`/auth/google/callback?state=${attempt.state}&code=${code}`)).status).toBe(200);
  const response = await request('/auth/google/finish', 'POST', { attemptToken: attempt.attemptToken });
  expect(response.status).toBe(200);
  return await response.json() as { token: string; user: { id: string; email: string } };
}
const bearer = (token: string) => ({ authorization: `Bearer ${token}` });
const folders = (name: string) => ({ folders: [{ name, routines: [{ name: `${name} rutina`, exercises: ['Press'] }] }] });
async function saveFolders(name: string | null, headers: Record<string, string>) {
  const current = await (await request('/routine-library', 'GET', undefined, headers)).json();
  const folderId = randomUUID();
  return request('/routine-library', 'PATCH', {
    version: current.version,
    folders: name ? [{ id: folderId, name, position: 0 }] : [],
    routines: name ? [{ id: randomUUID(), folderId, name: name + ' rutina', position: 0, exercises: ['Press'] }] : [],
    deletedFolders: current.folders.map((f: { id: string }) => f.id), deletedRoutines: [],
  }, headers);
}
const draft = (name: string) => ({ routineName: name, startedAt: '2026-10-14T10:00:00Z', originalExercises: ['Press'], exercises: [] });
const workout = (name: string, kg: number) => ({
  routineName: name, startedAt: '2026-10-14T10:00:00Z', completedAt: '2026-10-14T11:00:00Z', durationSeconds: 3600,
  exercises: [{ name: 'Press', muscleGroup: 'Pecho', sets: [{ type: 'normal', kg, reps: 10, completed: true }] }],
});

beforeAll(async () => {
  await admin`CREATE SCHEMA ${admin(schemaName)}`;
  await migrateAuth(client);
});
beforeEach(async () => {
  await client`TRUNCATE users CASCADE`;
  await db.insert(users).values({ id: legacyId, displayName: 'Datos compartidos existentes' });
  exchangeCalls = 0;
  app = createApp(db, config, provider);
});
afterAll(async () => {
  await client.end();
  await admin`DROP SCHEMA IF EXISTS ${admin(schemaName)} CASCADE`;
  await admin.end();
});

describe('Authentication and private accounts', () => {
  test('public deployments cannot enable the shared development account', () => {
    expect(() => validateAuthConfig({ ...config, skipLogin: true })).toThrow('SKIP_LOGIN=true');
    expect(() => validateAuthConfig({ ...config, webOrigin: undefined, skipLogin: true })).toThrow();
    expect(() => validateAuthConfig({ ...config, webOrigin: 'https://localhost.example.com', skipLogin: true })).toThrow();
    expect(() => validateAuthConfig({ ...config, webOrigin: 'http://localhost:5173', skipLogin: true })).not.toThrow();
  });

  test('every data route rejects anonymous requests; health stays public', async () => {
    expect((await request('/health')).status).toBe(200);
    for (const [path, method, body] of [
      ['/auth/me', 'GET'], ['/exercises', 'GET'], ['/routine-folders', 'GET'],
      ['/workout-sessions', 'GET'], ['/workout-draft', 'GET'], ['/workout-draft', 'DELETE'],
      ['/exercises/rest-timer?name=Press', 'GET'], ['/exercises/previous?name=Press', 'GET'],
      ['/exercises', 'POST', { name: 'Press', muscleGroup: 'Pecho' }],
      ['/exercises/rest-timer', 'PUT', { name: 'Press', restSeconds: 120 }],
      ['/routine-folders', 'PUT', folders('Private')], ['/workout-draft', 'PUT', draft('Private')],
      ['/workout-sessions', 'POST', workout('Private', 50)],
    ] as const) {
      const response = await request(path, method, body);
      expect(response.status, `${method} ${path}`).toBe(401);
      expect(response.headers.get('cache-control')).toBe('no-store');
    }
  });

  test('missing Google credentials give a recoverable unavailable response', async () => {
    app = createApp(db, { ...config, clientId: '', clientSecret: '' }, provider);
    expect((await request('/auth/google/start?web=1', 'POST')).status).toBe(503);
    expect(await db.select().from(loginAttempts)).toHaveLength(0);
  });

  test('registration leaves old shared data unassigned and uses stable Google identity', async () => {
    await client`INSERT INTO routine_folders (user_id, name, position) VALUES (${legacyId}, 'Old shared data', 0)`;
    const alice = await login('alice');
    await migrateAuth(client);
    const again = await login('alice');
    expect(again.user.id).toBe(alice.user.id);
    expect(alice.user.id).not.toBe(legacyId);
    expect(alice.user.email).toBe('alice@example.com');
    expect(await (await request('/routine-folders', 'GET', undefined, bearer(alice.token))).json()).toEqual([]);
    const [legacy] = await db.select().from(users).where(eq(users.id, legacyId));
    expect(legacy!.googleSubject).toBeNull();
    expect((await client`SELECT name FROM routine_folders WHERE user_id = ${legacyId}`)[0]!.name).toBe('Old shared data');
    const sessions = await db.select().from(authSessions);
    expect(sessions.some(session => session.tokenHash === tokenHash(alice.token))).toBe(true);
    expect(sessions.some(session => session.tokenHash === alice.token)).toBe(false);
  });

  test('routines, exercises, timers, drafts, history and records stay with their account', async () => {
    const alice = await login('alice');
    const bob = await login('bob');
    for (const [account, name, kg, restSeconds] of [[alice, 'Alice', 50, 120], [bob, 'Bob', 100, 240]] as const) {
      const headers = bearer(account.token);
      expect((await saveFolders(name, headers)).status).toBe(200);
      expect((await request('/exercises', 'POST', { name: `${name} exercise`, muscleGroup: name }, headers)).status).toBe(201);
      expect((await request('/exercises/rest-timer', 'PUT', { name: 'Press', restSeconds }, headers)).status).toBe(200);
      expect((await request('/workout-draft', 'PUT', draft(name), headers)).status).toBe(200);
      expect((await request('/workout-sessions', 'POST', workout(name, kg), headers)).status).toBe(201);
    }
    for (const [account, name, kg, restSeconds] of [[alice, 'Alice', 50, 120], [bob, 'Bob', 100, 240]] as const) {
      const headers = bearer(account.token);
      const get = async (path: string) => (await request(path, 'GET', undefined, headers)).json();
      expect(await get('/routine-folders')).toEqual(folders(name).folders);
      const ownExercises = await get('/exercises');
      expect(ownExercises.map((item: { name: string }) => item.name).sort()).toEqual([`${name} exercise`, 'Press'].sort());
      expect(await get('/exercises/rest-timer?name=Press')).toEqual({ restSeconds });
      expect((await get('/workout-draft')).routineName).toBe(name);
      const history = await get('/workout-sessions');
      expect(history.total).toBe(1);
      expect(history.sessions[0].routineName).toBe(name);
      expect(history.sessions[0].volumeKg).toBe(kg * 10);
      expect((await get('/exercises/previous?name=Press')).sets[0].kg).toBe(kg);
    }
    // Replacing/deleting Alice's data must leave Bob's data intact.
    expect((await saveFolders(null, bearer(alice.token))).status).toBe(200);
    expect((await request('/workout-draft', 'DELETE', undefined, bearer(alice.token))).status).toBe(200);
    expect((await request('/workout-draft', 'GET', undefined, bearer(alice.token))).status).toBe(404);
    expect((await (await request('/workout-draft', 'GET', undefined, bearer(bob.token))).json()).routineName).toBe('Bob');
    expect(await (await request('/routine-folders', 'GET', undefined, bearer(bob.token))).json()).toEqual(folders('Bob').folders);
  });

  test('a stale browser tab cannot read or overwrite the newly signed-in account', async () => {
    const alice = await login('alice');
    const bob = await login('bob');
    const staleHeaders = { cookie: `i7l_session=${bob.token}`, 'x-i7l-user': alice.user.id };
    for (const [path, method, body] of [
      ['/routine-folders', 'GET'], ['/routine-folders', 'PUT', folders('Alice stale tab')],
      ['/workout-sessions', 'POST', workout('Alice stale tab', 50)], ['/workout-draft', 'DELETE'],
    ] as const) {
      const response = await request(path, method, body, staleHeaders);
      expect(response.status).toBe(409);
      expect((await response.json()).code).toBe('SESSION_CHANGED');
    }
    expect(await (await request('/routine-folders', 'GET', undefined, bearer(bob.token))).json()).toEqual([]);
    expect((await (await request('/workout-sessions', 'GET', undefined, bearer(bob.token))).json()).total).toBe(0);
  });

  test('web OAuth requires the initiating browser cookie before exchanging the code', async () => {
    const attempt = await start(true);
    expect(attempt.attemptToken).toBeUndefined();
    const callback = `/auth/google/callback?state=${attempt.state}&code=alice`;
    expect((await request(callback)).status).toBe(400);
    expect((await request(callback, 'GET', undefined, { cookie: 'i7l_login=wrong' })).status).toBe(400);
    expect(exchangeCalls).toBe(0);
    const response = await request(callback, 'GET', undefined, { cookie: attempt.cookie });
    expect(response.status).toBe(303);
    expect(response.headers.get('location')).toBe(config.webOrigin + '/');
    const cookies = response.headers.getSetCookie();
    const sessionCookie = cookies.find(cookie => cookie.startsWith('i7l_session='))!;
    expect(sessionCookie).toContain('HttpOnly');
    expect(sessionCookie).toContain('SameSite=Lax');
    expect(sessionCookie).toContain('Secure');
    expect(cookies.some(cookie => cookie.startsWith('i7l_login=;') && cookie.includes('Max-Age=0'))).toBe(true);
    expect((await request('/auth/me', 'GET', undefined, { cookie: sessionCookie.split(';')[0]! })).status).toBe(200);
    expect((await request(callback, 'GET', undefined, { cookie: attempt.cookie })).status).toBe(400);
  });

  test('expired, cancelled and consumed login attempts cannot issue sessions', async () => {
    const expired = await start();
    await db.update(loginAttempts).set({ expiresAt: new Date(0) }).where(eq(loginAttempts.state, expired.state));
    expect((await request(`/auth/google/callback?state=${expired.state}&code=alice`)).status).toBe(400);
    expect((await request('/auth/google/finish', 'POST', { attemptToken: expired.attemptToken })).status).toBe(410);
    const cancelled = await start();
    expect((await request('/auth/google/cancel', 'POST', { attemptToken: cancelled.attemptToken })).status).toBe(200);
    expect((await request(`/auth/google/callback?state=${cancelled.state}&code=alice`)).status).toBe(400);
    const successful = await start();
    await request(`/auth/google/callback?state=${successful.state}&code=alice`);
    expect((await request('/auth/google/finish', 'POST', { attemptToken: successful.attemptToken })).status).toBe(200);
    expect((await request('/auth/google/finish', 'POST', { attemptToken: successful.attemptToken })).status).toBe(410);
    const denied = await start();
    expect((await request(`/auth/google/callback?state=${denied.state}&error=access_denied`)).status).toBe(400);
    expect((await request('/auth/google/finish', 'POST', { attemptToken: denied.attemptToken })).status).toBe(401);
  });

  test('logout and expiry revoke access without affecting another account', async () => {
    const alice = await login('alice');
    const bob = await login('bob');
    const logout = await request('/auth/session', 'DELETE', undefined, { cookie: `i7l_session=${alice.token}` });
    expect(logout.status).toBe(200);
    expect(logout.headers.get('set-cookie')).toContain('Max-Age=0');
    expect((await request('/exercises', 'GET', undefined, bearer(alice.token))).status).toBe(401);
    expect((await request('/exercises', 'GET', undefined, bearer(bob.token))).status).toBe(200);
    await db.update(authSessions).set({ expiresAt: new Date(0) }).where(eq(authSessions.tokenHash, tokenHash(bob.token)));
    expect((await request('/exercises', 'GET', undefined, bearer(bob.token))).status).toBe(401);
  });

  test('cross-origin writes fail before touching any data', async () => {
    const alice = await login('alice');
    const response = await request('/routine-folders', 'PUT', folders('Malicious'), { ...bearer(alice.token), origin: 'https://other.example.com' });
    expect(response.status).toBe(403);
    expect((await request('/auth/session', 'DELETE', undefined, { ...bearer(alice.token), 'sec-fetch-site': 'cross-site' })).status).toBe(403);
    expect(await (await request('/routine-folders', 'GET', undefined, bearer(alice.token))).json()).toEqual([]);
  });
});
