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
  await client`TRUNCATE exercise_catalog, users CASCADE`;
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
    [`/routines/${randomUUID()}/rest-timer`, 'GET'], [`/routines/${randomUUID()}/rest-timer`, 'PUT', { betweenExercisesSeconds: 90 }],
    ['/routine-recipients?q=ali', 'GET'], ['/routine-shares', 'GET'], ['/routine-shares/pending', 'GET'],
    ['/routine-shares', 'POST', { id: randomUUID(), routineId: randomUUID(), recipientId: bob.id, version: 0 }],
    ['/folder-shares', 'POST', { id: randomUUID(), folderId: randomUUID(), recipientId: bob.id, version: 0 }],
    [`/routine-shares/${randomUUID()}`, 'GET'], [`/routine-shares/${randomUUID()}/accept`, 'POST', {}],
    [`/routine-shares/${randomUUID()}/reject`, 'POST'], [`/routine-shares/${randomUUID()}/revoke`, 'POST'],
  ] as const) expect((await request(path, anonymous, method, body)).status).toBe(401);
});
test('routine rests default to three minutes and updates remain independent across routines and accounts', async () => {
  const a = await createRoutine(), b = await createRoutine(alice, 'Piernas'), c = await createRoutine(bob);
  const path = (id: string) => `/routines/${id}/rest-timer`;
  expect(await (await request(path(a.routineId))).json()).toEqual({ betweenExercisesSeconds: 180 });
  await request('/workout-settings', alice, 'PUT', { betweenExercisesSeconds: 90 }); // Legacy global preference.
  expect(await (await request(path(b.routineId))).json()).toEqual({ betweenExercisesSeconds: 180 });
  for (const seconds of [60, 90, 120, 150, 180, 210, 240, 270, 300]) {
    const response = await request(path(a.routineId), alice, 'PUT', { betweenExercisesSeconds: seconds });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ betweenExercisesSeconds: seconds });
    expect(await (await request(path(b.routineId))).json()).toEqual({ betweenExercisesSeconds: 180 });
    expect(await (await request(path(c.routineId), bob)).json()).toEqual({ betweenExercisesSeconds: 180 });
  }
  for (const value of [0, 59, 61, 301, 90.5, null]) expect((await request(path(a.routineId), alice, 'PUT', { betweenExercisesSeconds: value })).status).toBe(422);
  for (const id of [c.routineId, randomUUID()]) {
    expect((await request(path(id))).status).toBe(404);
    expect((await request(path(id), alice, 'PUT', { betweenExercisesSeconds: 90 })).status).toBe(404);
  }
  expect((await request('/routines/not-a-uuid/rest-timer')).status).toBe(422);
  // Editing a timer does not invalidate or overwrite a pending library edit.
  expect((await request('/routine-library', alice, 'PATCH', { ...emptyPatch(b.version),
    routines: [{ id: a.routineId, folderId: a.folderId, name: 'Nuevo nombre', position: 0, exercises: ['Press'] }] })).status).toBe(200);
  await migrateAuth(client);
  expect(await (await request(path(a.routineId))).json()).toEqual({ betweenExercisesSeconds: 300 });
  expect(await (await request('/workout-settings')).json()).toEqual({ betweenExercisesSeconds: 90 });
});

test('upgrading v34 starts each existing routine at three minutes without changing its other settings', async () => {
  const a = await createRoutine();
  await request('/workout-settings', alice, 'PUT', { betweenExercisesSeconds: 90 });
  await request('/exercises/rest-timer', alice, 'PUT', { name: 'Press', restSeconds: 60 });
  await client`ALTER TABLE routines DROP COLUMN between_exercises_seconds`;
  await migrateAuth(client);
  expect(await (await request(`/routines/${a.routineId}/rest-timer`)).json()).toEqual({ betweenExercisesSeconds: 180 });
  expect(await (await request('/exercises/rest-timer?name=Press')).json()).toEqual({ restSeconds: 60 });
  expect((await getLibrary()).folders[0].routines[0].exercises).toEqual(['Press', 'Elevaciones']);
});

test('shared routine rests are copied independently, and old shares keep the default', async () => {
  const a = await createRoutine();
  await request('/exercises/rest-timer', alice, 'PUT', { name: 'Press', restSeconds: 60 });
  await request('/exercises/rest-timer', alice, 'PUT', { name: 'Press', kind: 'exercises', restSeconds: 90 });
  await request(`/routines/${a.routineId}/rest-timer`, alice, 'PUT', { betweenExercisesSeconds: 90 });
  const shared = await send(a.routineId, a.version);
  await request('/exercises/rest-timer', alice, 'PUT', { name: 'Press', kind: 'exercises', restSeconds: 300 });
  await request(`/routines/${a.routineId}/rest-timer`, alice, 'PUT', { betweenExercisesSeconds: 300 });
  expect((await request(`/routine-shares/${shared.id}/accept`, bob, 'POST', {})).status).toBe(200);
  const copy = (await getLibrary(bob)).folders[0].routines[0];
  expect(await (await request('/exercises/rest-timer?name=Press', bob)).json()).toEqual({ restSeconds: 60 });
  expect(await (await request('/exercises/rest-timer?name=Press&kind=exercises', bob)).json()).toEqual({ restSeconds: 90 });
  await request('/exercises/rest-timer', bob, 'PUT', { name: 'Press', kind: 'exercises', restSeconds: 120 });
  expect(await (await request('/exercises/rest-timer?name=Press&kind=exercises')).json()).toEqual({ restSeconds: 300 });
  const again = await send(a.routineId, a.version);
  expect((await request(`/routine-shares/${again.id}/accept`, bob, 'POST', {})).status).toBe(200);
  expect(await (await request('/exercises/rest-timer?name=Press&kind=exercises', bob)).json()).toEqual({ restSeconds: 120 });
  expect(await (await request(`/routines/${copy.id}/rest-timer`, bob)).json()).toEqual({ betweenExercisesSeconds: 90 });
  await request(`/routines/${copy.id}/rest-timer`, bob, 'PUT', { betweenExercisesSeconds: 120 });
  expect(await (await request(`/routines/${a.routineId}/rest-timer`)).json()).toEqual({ betweenExercisesSeconds: 300 });
  const oldId = randomUUID();
  await db.insert(routineShares).values({ id: oldId, senderId: alice.id, recipientId: carol.id,
    snapshot: { version: 1, name: 'Anterior', exercises: [{ name: 'Press', muscleGroup: null, restSeconds: 60 }] } });
  expect((await request(`/routine-shares/${oldId}/accept`, carol, 'POST', {})).status).toBe(200);
  const oldCopy = (await getLibrary(carol)).folders[0].routines[0];
  expect(await (await request('/exercises/rest-timer?name=Press&kind=exercises', carol)).json()).toEqual({ restSeconds: 180 });
  expect(await (await request(`/routines/${oldCopy.id}/rest-timer`, carol)).json()).toEqual({ betweenExercisesSeconds: 180 });
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
  const catalog = await (await request('/exercises', carol)).json();
  expect(catalog.map((e: { name: string }) => e.name).sort()).toEqual(['Elevaciones', 'Press']);
  expect((await request('/exercises/previous?name=Press', carol)).status).toBe(404);
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
async function createPlan(user = alice) {
  const folderId = randomUUID();
  const version = (await getLibrary(user)).version;
  const entries = [
    { id: randomUUID(), name: 'Piernas', position: 2, exercises: [] },
    { id: randomUUID(), name: 'Empuje', position: 0, exercises: ['Press', 'Elevaciones'] },
    { id: randomUUID(), name: 'Tirón', position: 1, exercises: ['Remo', 'Press'] },
  ];
  expect((await request('/routine-library', user, 'PATCH', { ...emptyPatch(version),
    folders: [{ id: folderId, name: 'Semana completa', position: 0 }],
    routines: entries.map(r => ({ ...r, folderId })),
  })).status).toBe(200);
  return { folderId, version: version + 1, entries };
}
async function sendFolder(folderId: string, version: number, id: string = randomUUID()) {
  const response = await request('/folder-shares', alice, 'POST', { id, folderId, recipientId: bob.id, version });
  expect(response.status).toBe(200);
  return await response.json() as { id: string; status: string };
}

test('folder sharing validates ownership, recipient, revision and empty folders', async () => {
  const plan = await createPlan();
  const input = { id: randomUUID(), folderId: plan.folderId, recipientId: bob.id, version: plan.version };
  expect((await request('/folder-shares', carol, 'POST', { ...input, version: 0 })).status).toBe(404);
  expect((await request('/folder-shares', alice, 'POST', { ...input, recipientId: alice.id })).status).toBe(400);
  expect((await request('/folder-shares', alice, 'POST', { ...input, recipientId: randomUUID() })).status).toBe(404);
  expect((await request('/folder-shares', alice, 'POST', { ...input, version: 0 })).status).toBe(409);
  expect((await request('/folder-shares', alice, 'POST', { ...input, folderId: randomUUID() })).status).toBe(404);
  const empty = randomUUID();
  await request('/routine-library', alice, 'PATCH', { ...emptyPatch(plan.version), folders: [{ id: empty, name: 'Vacía', position: 1 }] });
  const rejected = await request('/folder-shares', alice, 'POST', { ...input, folderId: empty, version: plan.version + 1 });
  expect(rejected.status).toBe(400);
  expect((await rejected.json()).code).toBe('EMPTY_FOLDER');
  expect(await db.select().from(routineShares)).toHaveLength(0);
});

test('upgrading the routine-only schema preserves pending individual shares', async () => {
  const r = await createRoutine();
  const share = await send(r.routineId, r.version);
  // The test connection uses its own disposable schema, never application data.
  await client`ALTER TABLE routine_shares DROP COLUMN source_folder_id CASCADE, DROP COLUMN imported_folder_id CASCADE`;
  await migrateAuth(client);
  await migrateAuth(client);
  const pending = await (await request('/routine-shares', bob)).json();
  expect(pending.items[0]).toMatchObject({ id: share.id, name: 'Empuje', kind: 'routine' });
  expect((await request(`/routine-shares/${share.id}/accept`, bob, 'POST', {})).status).toBe(200);
  expect((await getLibrary(bob)).folders[0].routines[0].exercises).toEqual(['Press', 'Elevaciones']);
});

test('folder sends are idempotent and older clients keep a routine-only inbox', async () => {
  const plan = await createPlan();
  const share = await sendFolder(plan.folderId, plan.version);
  expect((await sendFolder(plan.folderId, plan.version)).id).toBe(share.id);
  expect((await sendFolder(plan.folderId, 0, share.id)).id).toBe(share.id);
  expect((await (await request('/routine-shares', bob)).json()).items).toEqual([]);
  expect(await (await request('/routine-shares/pending', bob)).json()).toEqual({ pending: false });
  expect(await (await request('/routine-shares/pending?includeFolders=true', bob)).json()).toEqual({ pending: true });
  const page = await (await request('/routine-shares?includeFolders=true', bob)).json();
  expect(page.items).toHaveLength(1);
  expect(page.items[0]).toMatchObject({ id: share.id, kind: 'folder', routineCount: 3, exerciseCount: 4, name: 'Semana completa' });
  expect((await request(`/routine-shares/${share.id}`, carol)).status).toBe(404);
  expect((await request(`/routine-shares/${share.id}/accept`, alice, 'POST', {})).status).toBe(404);
  expect((await request('/routine-shares', alice, 'POST', { id: share.id, routineId: plan.entries[0].id, recipientId: bob.id, version: plan.version })).status).toBe(409);
  await migrateAuth(client);
  expect((await (await request('/routine-shares?includeFolders=true', bob)).json()).items).toHaveLength(1);
});

test('accepting a folder copies every routine in order, preserves settings and survives source deletion', async () => {
  const plan = await createPlan();
  await db.insert(exercises).values([
    { userId: alice.id, name: 'Press', normalizedName: 'press', muscleGroup: 'Pecho', restSeconds: 120 },
    { userId: alice.id, name: 'Remo', normalizedName: 'remo', muscleGroup: 'Dorsales', restSeconds: 90 },
    { userId: bob.id, name: 'Press', normalizedName: 'press', muscleGroup: 'Personal', restSeconds: 240 },
  ]);
  const existing = await createRoutine(bob, 'Mi rutina');
  const share = await sendFolder(plan.folderId, plan.version);
  await request('/routine-library', alice, 'PATCH', { ...emptyPatch(plan.version), deletedFolders: [plan.folderId] });
  const detail = await (await request(`/routine-shares/${share.id}`, bob)).json();
  expect(detail.snapshot.version).toBe(2);
  expect(detail.snapshot.routines.map((r: { name: string }) => r.name)).toEqual(['Empuje', 'Tirón', 'Piernas']);
  expect(detail.snapshot.routines[0].exercises[0]).toMatchObject({ name: 'Press', muscleGroup: 'Pecho', restSeconds: 120 });
  expect((await request(`/routine-shares/${share.id}/accept`, bob, 'POST', { folderId: existing.folderId })).status).toBe(400);
  expect((await getLibrary(bob)).folders).toHaveLength(1);
  const responses = await Promise.all([request(`/routine-shares/${share.id}/accept`, bob, 'POST', {}), request(`/routine-shares/${share.id}/accept`, bob, 'POST', {})]);
  expect(responses.map(r => r.status)).toEqual([200, 200]);
  const [first, retry] = await Promise.all(responses.map(r => r.json()));
  expect(first.folderId).toBe(retry.folderId);
  expect(first.folderId).not.toBe(plan.folderId);
  const library = await getLibrary(bob);
  expect(library.version).toBe(existing.version + 1);
  expect(library.folders).toHaveLength(2);
  const imported = library.folders[1];
  expect(imported.name).toBe('Semana completa');
  expect(imported.routines.map((r: { name: string }) => r.name)).toEqual(['Empuje', 'Tirón', 'Piernas']);
  expect(imported.routines.map((r: { exercises: string[] }) => r.exercises)).toEqual([['Press', 'Elevaciones'], ['Remo', 'Press'], []]);
  expect(imported.routines.every((r: { id: string }) => !plan.entries.some(e => e.id === r.id))).toBe(true);
  expect(await (await request('/exercises/rest-timer?name=Press', bob)).json()).toEqual({ restSeconds: 240 });
  expect(await (await request('/exercises/rest-timer?name=Remo', bob)).json()).toEqual({ restSeconds: 90 });
  expect((await (await request('/workout-sessions', bob)).json()).total).toBe(0);
  expect((await request('/exercises/previous?name=Press', bob)).status).toBe(404);
  expect((await request('/routine-library', bob, 'PATCH', emptyPatch(existing.version))).status).toBe(409);
  await request('/routine-library', bob, 'PATCH', { ...emptyPatch(library.version), deletedFolders: [imported.id] });
  expect((await request(`/routine-shares/${share.id}/accept`, bob, 'POST', {})).status).toBe(200);
  expect((await getLibrary(bob)).folders).toHaveLength(1);
});

test('imported folder copies are independent and folder rejection/cancellation create no data', async () => {
  const plan = await createPlan();
  const share = await sendFolder(plan.folderId, plan.version);
  await request(`/routine-shares/${share.id}/accept`, bob, 'POST', {});
  const received = await getLibrary(bob);
  await request('/routine-library', bob, 'PATCH', { ...emptyPatch(received.version),
    routines: [{ id: received.folders[0].routines[0].id, folderId: received.folders[0].id, name: 'Mi copia', position: 0, exercises: ['Otro'] }],
  });
  expect((await getLibrary()).folders[0].routines[0].name).toBe('Empuje');
  const another = await sendFolder(plan.folderId, plan.version);
  expect((await request(`/routine-shares/${another.id}/reject`, alice, 'POST')).status).toBe(404);
  expect((await request(`/routine-shares/${another.id}/reject`, bob, 'POST')).status).toBe(200);
  expect((await request(`/routine-shares/${another.id}/accept`, bob, 'POST', {})).status).toBe(409);
  const cancelled = await sendFolder(plan.folderId, plan.version);
  expect((await request(`/routine-shares/${cancelled.id}/revoke`, alice, 'POST')).status).toBe(200);
  expect((await request(`/routine-shares/${cancelled.id}/accept`, bob, 'POST', {})).status).toBe(409);
  expect((await getLibrary(bob)).folders).toHaveLength(1);
});

test('folder snapshot limits bound routine and exercise counts', async () => {
  const folderId = randomUUID();
  const entries = Array.from({ length: 101 }, (_, i) => ({ id: randomUUID(), folderId, name: `Día ${i}`, position: i, exercises: [] as string[] }));
  await request('/routine-library', alice, 'PATCH', { ...emptyPatch(0), folders: [{ id: folderId, name: 'Plan', position: 0 }], routines: entries });
  let response = await request('/folder-shares', alice, 'POST', { id: randomUUID(), folderId, recipientId: bob.id, version: 1 });
  expect(response.status).toBe(400);
  expect((await response.json()).code).toBe('FOLDER_TOO_LARGE');
  await request('/routine-library', alice, 'PATCH', { ...emptyPatch(1), deletedRoutines: entries.slice(6).map(r => r.id),
    routines: entries.slice(0, 6).map(r => ({ ...r, exercises: Array.from({ length: 100 }, (_, i) => `Ejercicio ${i}`) })) });
  response = await request('/folder-shares', alice, 'POST', { id: randomUUID(), folderId, recipientId: bob.id, version: 2 });
  expect(response.status).toBe(400);
  expect((await response.json()).code).toBe('FOLDER_TOO_LARGE');
});

test('mixed folder/routine inbox pages stay private and do not omit tied timestamps', async () => {
  const at = new Date();
  await db.insert(routineShares).values(Array.from({ length: 43 }, (_, i) => ({
    id: randomUUID(), senderId: alice.id, recipientId: bob.id, createdAt: at,
    snapshot: i % 2 === 0 ? { version: 2 as const, name: `Folder ${i}`, routines: [{ name: 'Día', exercises: [] }] }
      : { version: 1 as const, name: `Routine ${i}`, exercises: [] },
  })));
  const collected: string[] = []; let cursor: string | null = null;
  do {
    const page = await (await request('/routine-shares?includeFolders=true' + (cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''), bob)).json();
    expect(page.items.length).toBeLessThanOrEqual(20);
    collected.push(...page.items.map((i: { id: string }) => i.id)); cursor = page.nextCursor;
    expect(collected.length).toBeLessThanOrEqual(43);
  } while (cursor);
  expect(collected).toHaveLength(43);
  expect(new Set(collected).size).toBe(43);
  for (const path of ['/routine-shares?includeFolders=true', '/routine-shares?includeFolders=true&direction=sent']) {
    expect((await (await request(path, carol)).json()).items).toEqual([]);
  }
  expect((await (await request('/routine-shares?direction=sent&includeFolders=true', bob)).json()).items).toEqual([]);
  expect((await (await request('/routine-shares?includeFolders=true&direction=sent', alice)).json()).items).toHaveLength(20);
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
