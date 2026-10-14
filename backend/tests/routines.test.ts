import { afterAll, beforeAll, beforeEach, expect, test } from 'bun:test';
import { randomBytes, randomUUID } from 'node:crypto';
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import { eq } from 'drizzle-orm';
import { createApp } from '../index.ts';
import { migrateAuth } from '../auth-migration.ts';
import { tokenHash } from '../auth.ts';
import { authSessions, exercises, routineExercises, routineShares, users } from '../schema.ts';

const url = process.env.TEST_DATABASE_URL;
if (!url) throw new Error('Configura TEST_DATABASE_URL para probar en PostgreSQL.');
const schema = `hevy_routines_test_${randomUUID().replaceAll('-', '')}`;
const admin = postgres(url, { max: 1, onnotice: () => {} });
const client = postgres(url, { max: 5, connection: { search_path: schema }, onnotice: () => {} });
const db = drizzle(client);
const accounts = ['alice', 'bob', 'carol'].map(name => ({ id: randomUUID(), name, token: randomBytes(32).toString('base64url'), email: `${name}@gmail.com` }));
const [alice, bob, carol] = accounts;
let app: ReturnType<typeof createApp>;
function request(path: string, user = alice, method = 'GET', body?: unknown) {
  return app.handle(new Request(`http://localhost${path}`, { method,
    headers: { authorization: `Bearer ${user.token}`, ...(body === undefined ? {} : { 'content-type': 'application/json' }) },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }));
}
async function getLibrary(user = alice) { return (await request('/routine-library', user)).json(); }
const emptyPatch = (version: number) => ({ version, folders: [] as unknown[], routines: [] as unknown[], deletedFolders: [] as string[], deletedRoutines: [] as string[] });
async function createRoutine(user = alice, name = 'Empuje', names = ['Press', 'Elevaciones']) {
  const folderId = randomUUID(), routineId = randomUUID();
  const library = await getLibrary(user);
  const patch = { ...emptyPatch(library.version), folders: [{ id: folderId, name: 'Plan', position: library.folders.length }],
    routines: [{ id: routineId, folderId, name, position: 0, exercises: names }] };
  expect((await request('/routine-library', user, 'PATCH', patch)).status).toBe(200);
  return { folderId, routineId, version: library.version + 1 };
}
async function send(routineId: string, version: number, recipient = bob, sender = alice, id: string = randomUUID()) {
  const response = await request('/routine-shares', sender, 'POST', { id, routineId, recipientId: recipient.id, version });
  expect(response.status).toBe(200);
  return await response.json() as { id: string; status: string };
}
beforeAll(async () => { await admin`CREATE SCHEMA ${admin(schema)}`; await migrateAuth(client); });
beforeEach(async () => {
  await client`TRUNCATE users CASCADE`;
  for (const a of accounts) {
    await db.insert(users).values({ id: a.id, email: a.email, googleSubject: a.name, displayName: a.email });
    await db.insert(authSessions).values({ userId: a.id, tokenHash: tokenHash(a.token), expiresAt: new Date(Date.now() + 3600000) });
  }
  app = createApp(db, { clientId: 'test', clientSecret: 'test', webOrigin: 'https://app.i7l.cl', redirectUri: 'https://app.i7l.cl/api/auth/google/callback' });
});
afterAll(async () => { await client.end(); await admin`DROP SCHEMA ${admin(schema)} CASCADE`; await admin.end(); });

test('all new endpoints require authentication', async () => {
  const anonymous = { ...alice, token: 'invalid' };
  for (const [path, method, body] of [
    ['/routine-library', 'GET'], ['/routine-library', 'PATCH', emptyPatch(0)],
    ['/routine-recipients?q=ali', 'GET'], ['/routine-shares', 'GET'], ['/routine-shares/pending', 'GET'],
    ['/routine-shares', 'POST', { id: randomUUID(), routineId: randomUUID(), recipientId: bob.id, version: 0 }],
    [`/routine-shares/${randomUUID()}`, 'GET'], [`/routine-shares/${randomUUID()}/accept`, 'POST', {}],
    [`/routine-shares/${randomUUID()}/reject`, 'POST'], [`/routine-shares/${randomUUID()}/revoke`, 'POST'],
  ] as const) expect((await request(path, anonymous, method, body)).status).toBe(401);
});
test('account search is bounded, case insensitive, literal and excludes self/legacy', async () => {
  await db.insert(users).values(Array.from({ length: 16 }, (_, i) => ({ displayName: 'Private name', googleSubject: `alex-${i}`, email: `alex${i}@gmail.com` })));
  await db.insert(users).values({ displayName: 'Not Google', email: 'alex-local@gmail.com' });
  expect(await (await request('/routine-recipients?q=al')).json()).toEqual([]);
  const matches = await (await request('/routine-recipients?q=ALe')).json();
  expect(matches).toHaveLength(10);
  expect(Object.keys(matches[0]).sort()).toEqual(['email', 'id']);
  expect(matches.every((m: { email: string }) => m.email.startsWith('alex'))).toBe(true);
  expect(await (await request('/routine-recipients?q=alice')).json()).toEqual([]);
  expect(await (await request('/routine-recipients?q=ale%25')).json()).toEqual([]);
  expect(await (await request('/routine-recipients?q=%25%25%25')).json()).toEqual([]);
  expect(await (await request('/routine-recipients?q=gmail')).json()).toEqual([]);
  expect((await request('/routine-recipients?q=' + 'a'.repeat(255))).status).toBe(422);
});
test('search rate limiting stops repeated enumeration', async () => {
  for (let i = 0; i < 30; i++) expect((await request('/routine-recipients?q=bob')).status).toBe(200);
  expect((await request('/routine-recipients?q=bob')).status).toBe(429);
  expect((await request('/routine-recipients?q=ali', bob)).status).toBe(200);
});
test('patch preserves folder/routine/exercise IDs and migration preserves data', async () => {
  const r = await createRoutine();
  const beforeExercises = await db.select().from(routineExercises);
  const patch = { ...emptyPatch(r.version), routines: [{ id: r.routineId, folderId: r.folderId, name: 'Nuevo nombre', position: 0 }] };
  expect((await request('/routine-library', alice, 'PATCH', patch)).status).toBe(200);
  await migrateAuth(client);
  expect((await getLibrary()).folders[0].routines[0].id).toBe(r.routineId);
  expect(await db.select().from(routineExercises)).toEqual(beforeExercises);
  expect((await getLibrary()).folders[0].id).toBe(r.folderId);
  const noChange = await request('/routine-library', alice, 'PATCH', emptyPatch(r.version + 1));
  expect(await noChange.json()).toEqual({ version: r.version + 1 });
});
test('patch cannot modify another account or create a routine under its folder; rolls back', async () => {
  const r = await createRoutine(bob);
  const library = await getLibrary();
  for (const patch of [
    { ...emptyPatch(library.version), deletedFolders: [r.folderId] },
    { ...emptyPatch(library.version), deletedRoutines: [r.routineId] },
    { ...emptyPatch(library.version), folders: [{ id: r.folderId, name: 'Steal', position: 0 }] },
    { ...emptyPatch(library.version), routines: [{ id: r.routineId, folderId: randomUUID(), name: 'Steal', position: 0 }] },
    { ...emptyPatch(library.version), folders: [{ id: randomUUID(), name: 'Rollback', position: 0 }], routines: [{ id: randomUUID(), folderId: r.folderId, name: 'Steal', position: 0 }] },
  ]) expect((await request('/routine-library', alice, 'PATCH', patch)).status).toBe(404);
  expect((await getLibrary()).folders).toEqual([]);
  expect((await getLibrary(bob)).folders[0].routines[0].name).toBe('Empuje');
});
test('concurrent library updates reject the stale revision; older clients cannot replace the library', async () => {
  const r = await createRoutine();
  const results = await Promise.all(['A', 'B'].map(name => request('/routine-library', alice, 'PATCH', {
    ...emptyPatch(r.version), routines: [{ id: r.routineId, folderId: r.folderId, name, position: 0 }],
  })));
  expect(results.map(r => r.status).sort()).toEqual([200, 409]);
  expect((await request('/routine-folders', alice, 'PUT', { folders: [] })).status).toBe(428);
  expect((await getLibrary()).folders[0].routines).toHaveLength(1);
});
test('sending checks ownership, account existence, self, empty content and duplicate pending sends', async () => {
  const r = await createRoutine();
  const body = { id: randomUUID(), routineId: r.routineId, recipientId: bob.id, version: r.version };
  expect((await request('/routine-shares', carol, 'POST', { ...body, version: 0 })).status).toBe(404);
  expect((await request('/routine-shares', alice, 'POST', { ...body, recipientId: alice.id })).status).toBe(400);
  expect((await request('/routine-shares', alice, 'POST', { ...body, recipientId: randomUUID() })).status).toBe(404);
  expect((await request('/routine-shares', alice, 'POST', { ...body, version: 0 })).status).toBe(409);
  const first = await send(r.routineId, r.version);
  expect((await send(r.routineId, r.version)).id).toBe(first.id);
  expect((await send(r.routineId, r.version, bob, alice, first.id)).id).toBe(first.id);
  expect(await db.select().from(routineShares)).toHaveLength(1);
  const empty = await createRoutine(alice, 'Vacía', []);
  expect((await request('/routine-shares', alice, 'POST', { ...body, id: randomUUID(), routineId: empty.routineId, version: empty.version })).status).toBe(400);
});
test('snapshot survives source edits/deletion; accept copies settings without private records', async () => {
  const r = await createRoutine();
  await db.insert(exercises).values({ userId: alice.id, name: 'Press', normalizedName: 'press', muscleGroup: 'Pecho', restSeconds: 120 });
  await db.insert(exercises).values({ userId: bob.id, name: 'Press', normalizedName: 'press', muscleGroup: 'Personal', restSeconds: 240 });
  const share = await send(r.routineId, r.version);
  expect(await (await request('/routine-shares/pending', bob)).json()).toEqual({ pending: true });
  expect(await (await request('/routine-shares/pending', carol)).json()).toEqual({ pending: false });
  expect((await request(`/routine-shares/${share.id}`, carol)).status).toBe(404);
  expect((await request(`/routine-shares/${share.id}/accept`, alice, 'POST', {})).status).toBe(404);
  await request('/routine-library', alice, 'PATCH', { ...emptyPatch(r.version), deletedFolders: [r.folderId] });
  const detail = await (await request(`/routine-shares/${share.id}`, bob)).json();
  expect(detail.snapshot.name).toBe('Empuje');
  expect(detail.snapshot.exercises.map((e: { name: string }) => e.name)).toEqual(['Press', 'Elevaciones']);
  const [a, b] = await Promise.all([request(`/routine-shares/${share.id}/accept`, bob, 'POST', {}), request(`/routine-shares/${share.id}/accept`, bob, 'POST', {})]);
  expect(a.status).toBe(200); expect(b.status).toBe(200);
  expect((await a.json()).routineId).toBe((await b.json()).routineId);
  const library = await getLibrary(bob);
  expect(library.folders[0].name).toBe('Recibidas');
  expect(library.folders[0].routines).toHaveLength(1);
  expect(library.folders[0].routines[0].exercises).toEqual(['Press', 'Elevaciones']);
  expect(await (await request('/workout-sessions', bob)).json()).toMatchObject({ total: 0 });
  expect((await request('/exercises/previous?name=Press', bob)).status).toBe(404);
  expect(await (await request('/exercises/rest-timer?name=Press', bob)).json()).toEqual({ restSeconds: 240 });
  expect(await (await request('/routine-shares/pending', bob)).json()).toEqual({ pending: false });
});
test('received settings import into a new account; recipient edits leave sender untouched', async () => {
  const r = await createRoutine();
  await db.insert(exercises).values({ userId: alice.id, name: 'Press', normalizedName: 'press', muscleGroup: 'Pecho', restSeconds: 120 });
  const share = await send(r.routineId, r.version);
  await request(`/routine-shares/${share.id}/accept`, bob, 'POST', {});
  expect(await (await request('/exercises/rest-timer?name=Press', bob)).json()).toEqual({ restSeconds: 120 });
  const library = await getLibrary(bob), f = library.folders[0], copy = f.routines[0];
  await request('/routine-library', bob, 'PATCH', { ...emptyPatch(library.version), routines: [{ id: copy.id, folderId: f.id, name: 'Mi versión', position: 0, exercises: ['Otro'] }] });
  expect((await getLibrary()).folders[0].routines[0].name).toBe('Empuje');
  // A retry after deleting an accepted copy must never recreate it.
  await request('/routine-library', bob, 'PATCH', { ...emptyPatch(library.version + 1), deletedFolders: [f.id] });
  expect((await request(`/routine-shares/${share.id}/accept`, bob, 'POST', {})).status).toBe(200);
  expect((await getLibrary(bob)).folders).toEqual([]);
});
test('acceptance invalidates stale writes and validates the chosen destination folder', async () => {
  const r = await createRoutine(), destination = await createRoutine(bob);
  const share = await send(r.routineId, r.version);
  expect((await request(`/routine-shares/${share.id}/accept`, bob, 'POST', { folderId: r.folderId })).status).toBe(404);
  expect((await request(`/routine-shares/${share.id}/accept`, bob, 'POST', { folderId: destination.folderId })).status).toBe(200);
  expect((await request('/routine-library', bob, 'PATCH', { ...emptyPatch(destination.version), deletedFolders: [destination.folderId] })).status).toBe(409);
  expect((await getLibrary(bob)).folders[0].routines).toHaveLength(2);
});
test('only sender revokes/only recipient rejects; accept/cancel races have one winner', async () => {
  const r = await createRoutine(), share = await send(r.routineId, r.version);
  expect((await request(`/routine-shares/${share.id}/revoke`, bob, 'POST')).status).toBe(404);
  expect((await request(`/routine-shares/${share.id}/reject`, alice, 'POST')).status).toBe(404);
  const results = await Promise.all([request(`/routine-shares/${share.id}/accept`, bob, 'POST', {}), request(`/routine-shares/${share.id}/revoke`, alice, 'POST')]);
  expect(results.map(r => r.status).sort()).toEqual([200, 409]);
  const second = await send(r.routineId, r.version, carol);
  expect((await request(`/routine-shares/${second.id}/reject`, carol, 'POST')).status).toBe(200);
  expect((await request(`/routine-shares/${second.id}/reject`, carol, 'POST')).status).toBe(200);
  expect((await request(`/routine-shares/${second.id}/accept`, carol, 'POST', {})).status).toBe(409);
});
test('keyset pagination is private and has no omissions when timestamps tie', async () => {
  const at = new Date();
  await db.insert(routineShares).values(Array.from({ length: 43 }, (_, i) => ({ id: randomUUID(), senderId: alice.id, recipientId: bob.id, createdAt: at,
    snapshot: { version: 1 as const, name: `Routine ${i}`, exercises: [] } })));
  const collected: string[] = []; let cursor: string | null = null;
  do {
    const page = await (await request('/routine-shares' + (cursor ? `?cursor=${encodeURIComponent(cursor)}` : ''), bob)).json();
    expect(page.items.length).toBeLessThanOrEqual(20);
    expect(page.items.every((i: { snapshot?: unknown }) => i.snapshot === undefined)).toBe(true);
    collected.push(...page.items.map((i: { id: string }) => i.id)); cursor = page.nextCursor;
  } while (cursor);
  expect(collected).toHaveLength(43); expect(new Set(collected).size).toBe(43);
  expect((await (await request('/routine-shares', carol)).json()).items).toEqual([]);
  expect((await request('/routine-shares?cursor=invalid', bob)).status).toBe(400);
});
test('representative directory and inbox queries use their indexes', async () => {
  await client`INSERT INTO users(display_name, email, google_subject)
    SELECT 'Load fixture', 'load' || lpad(n::text, 6, '0') || '@gmail.com', 'fixture-' || n FROM generate_series(1, 50000) n`;
  await client`INSERT INTO routine_shares(id, sender_id, recipient_id, snapshot)
    SELECT gen_random_uuid(), ${alice.id}, id, '{"version":1,"name":"Fixture","exercises":[]}'::jsonb FROM users WHERE google_subject LIKE 'fixture-%'`;
  await client`INSERT INTO routine_shares(id, sender_id, recipient_id, snapshot, status)
    SELECT gen_random_uuid(), ${alice.id}, ${bob.id}, '{"version":1,"name":"Inbox fixture","exercises":[]}'::jsonb,
      CASE WHEN n % 3 = 0 THEN 'pending' ELSE 'accepted' END FROM generate_series(1, 300) n`;
  await client`ANALYZE users`; await client`ANALYZE routine_shares`;
  const directory = await client`EXPLAIN (ANALYZE, BUFFERS) SELECT id, email FROM users
    WHERE google_subject IS NOT NULL AND email IS NOT NULL
    AND lower(email) COLLATE "C" >= ${'load025'} AND lower(email) COLLATE "C" < ${'load026'} AND id <> ${alice.id}
    ORDER BY lower(email) COLLATE "C" LIMIT 10`;
  const inbox = await client`EXPLAIN (ANALYZE, BUFFERS) SELECT id FROM routine_shares WHERE recipient_id = ${bob.id} AND status = 'pending' ORDER BY created_at DESC, id DESC LIMIT 21`;
  expect(JSON.stringify(directory)).toContain('users_email_prefix_idx');
  expect(JSON.stringify(inbox)).toContain('routine_shares_recipient_idx');
  const page = await (await request('/routine-shares', bob)).json();
  expect(page.items).toHaveLength(20);
  expect(page.nextCursor).not.toBeNull();
  console.log('Directory/inbox EXPLAIN:', directory.map(r => r['QUERY PLAN']).join('\n'), inbox.map(r => r['QUERY PLAN']).join('\n'));
}, 15000);
