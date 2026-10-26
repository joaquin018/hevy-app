import { afterAll, beforeAll, beforeEach, expect, test } from 'bun:test';
import { randomBytes, randomUUID } from 'node:crypto';
import { eq } from 'drizzle-orm';
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import { migrateAuth } from '../auth-migration.ts';
import { tokenHash } from '../auth.ts';
import { createApp } from '../index.ts';
import { authSessions, users, workoutSessions } from '../schema.ts';

const url = process.env.TEST_DATABASE_URL;
if (!url) throw new Error('Configura TEST_DATABASE_URL para probar en PostgreSQL.');
const schema = `hevy_scope_test_${randomUUID().replaceAll('-', '')}`;
const admin = postgres(url, { max: 1, onnotice: () => {} });
const client = postgres(url, { max: 5, connection: { search_path: schema }, onnotice: () => {} });
const db = drizzle(client);
const [alice, bob] = ['alice', 'bob'].map(name => ({ id: randomUUID(), name, token: randomBytes(32).toString('base64url') }));
const folderId = randomUUID(), monday = randomUUID(), thursday = randomUUID();
let app: ReturnType<typeof createApp>;
let sequence = 0;
function request(path: string, method = 'GET', body?: unknown, user = alice) {
  return app.handle(new Request(`http://localhost${path}`, { method,
    headers: { authorization: `Bearer ${user.token}`, ...(body === undefined ? {} : { 'content-type': 'application/json' }) },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }));
}
const json = async (path: string) => (await request(path)).json();
const set = (kg: number, reps = 10, type = 'normal', completed = true) => ({ kg, reps, type, completed });
async function patch(routines: unknown[], deletedRoutines: string[] = [], user = alice) {
  const { version } = await (await request('/routine-library', 'GET', undefined, user)).json();
  return request('/routine-library', 'PATCH', { version, folders: [], deletedFolders: [], deletedRoutines, routines }, user);
}
async function toggle(id: string, isolateResults: boolean, name = id === monday ? 'Lunes' : 'Jueves') {
  const response = await patch([{ id, folderId, name, position: id === monday ? 0 : 1, isolateResults }]);
  expect(response.status).toBe(200);
}
async function save(routineId: string | undefined, sets = [set(50)], routineName = routineId === monday ? 'Lunes' : 'Jueves', user = alice) {
  const startedAt = new Date(Date.UTC(2026, 9, 1 + sequence++, 10));
  const response = await request('/workout-sessions', 'POST', {
    routineId, routineName, startedAt: startedAt.toISOString(), completedAt: new Date(+startedAt + 3600000).toISOString(),
    durationSeconds: 3600, exercises: [{ name: 'Press', sets }],
  }, user);
  expect(response.status).toBe(201);
  return await response.json() as { id: string; completedAt: string };
}
const previous = (routineId?: string, user = alice) => request(`/exercises/previous?name=Press${routineId ? `&routineId=${routineId}` : ''}`, 'GET', undefined, user);
const values = async (id?: string) => (await (await previous(id)).json()).sets;
const draft = (routineId: string) => ({ routineId, routineName: 'Jueves', startedAt: '2026-10-26T10:00:00Z', originalExercises: ['Press'], exercises: [] });

beforeAll(async () => { await admin`CREATE SCHEMA ${admin(schema)}`; await migrateAuth(client); });
beforeEach(async () => {
  await client`TRUNCATE exercise_catalog, users CASCADE`;
  sequence = 0;
  for (const u of [alice, bob]) {
    await db.insert(users).values({ id: u.id, displayName: u.name, email: `${u.name}@gmail.com`, googleSubject: u.name });
    await db.insert(authSessions).values({ userId: u.id, tokenHash: tokenHash(u.token), expiresAt: new Date(Date.now() + 3600000) });
  }
  app = createApp(db, { clientId: 'test', clientSecret: 'test', webOrigin: 'https://app.i7l.cl', redirectUri: 'https://app.i7l.cl/api/auth/google/callback' });
  const response = await request('/routine-library', 'PATCH', { version: 0, deletedFolders: [], deletedRoutines: [],
    folders: [{ id: folderId, name: 'Plan', position: 0 }],
    routines: [{ id: monday, folderId, name: 'Lunes', position: 0, exercises: ['Press'] },
      { id: thursday, folderId, name: 'Jueves', position: 1, exercises: ['Press'] }],
  });
  expect(response.status).toBe(200);
});
afterAll(async () => { await client.end(); await admin`DROP SCHEMA ${admin(schema)} CASCADE`; await admin.end(); });

test('opt-in separates raw results from the shared pool and includes this routine past sessions only', async () => {
  await save(monday, [set(80)]);
  const old = await save(thursday, [set(22, 12, 'warmup'), set(58, 9)]);
  expect((await values(thursday))[0].kg).toBe(22); // Existing higher-weight OR higher-reps policy.
  await toggle(thursday, true);
  expect(await values(thursday)).toEqual([
    { position: 0, type: 'warmup', kg: 22, reps: 12 }, { position: 1, type: 'normal', kg: 58, reps: 9 },
  ]);
  expect((await (await previous(thursday)).json()).completedAt).toBe(old.completedAt);
  expect(await values(monday)).toEqual([{ position: 0, type: 'normal', kg: 80, reps: 10 }]);
  await save(thursday, [set(30, 12, 'failure')]);
  expect((await values())[0].kg).toBe(80);
  expect((await values(thursday))[0]).toMatchObject({ kg: 30, type: 'failure' });
  const library = await json('/routine-library');
  expect(library.folders[0].routines[1].isolateResults).toBe(true);
  expect(library.folders[0].routines[0].isolateResults).toBeUndefined();
});

test('an isolated routine with no completed sets never falls back to another routine', async () => {
  await save(monday, [set(100)]);
  await toggle(thursday, true);
  expect((await previous(thursday)).status).toBe(404);
  await save(thursday, [set(500, 10, 'normal', false)]);
  expect((await previous(thursday)).status).toBe(404);
  expect((await values(monday))[0].kg).toBe(100);
});

test('switching back rejoins the shared pool without deleting sessions', async () => {
  await save(monday, [set(50)]);
  await toggle(thursday, true);
  await save(thursday, [set(80)]);
  expect((await values())[0].kg).toBe(50);
  await toggle(thursday, false);
  expect((await values(monday))[0].kg).toBe(80);
  expect((await values(thursday))[0].kg).toBe(80);
  await toggle(thursday, true);
  expect((await values())[0].kg).toBe(50);
  expect((await json('/workout-sessions')).total).toBe(2);
});

test('history badges and deletion use each scope independently', async () => {
  await save(monday, [set(80)]);
  const baseline = await save(thursday, [set(40)]);
  const improvement = await save(thursday, [set(50)]);
  await toggle(thursday, true);
  let history = await json('/workout-sessions');
  expect(history.sessions.find((s: { id: string }) => s.id === baseline.id).records).toBe(0);
  expect(history.sessions.find((s: { id: string }) => s.id === improvement.id).records).toBe(1);
  expect((await request(`/workout-sessions/${improvement.id}`, 'DELETE')).status).toBe(200);
  expect((await values(thursday))[0].kg).toBe(40);
  expect((await values())[0].kg).toBe(80);
  expect((await request(`/workout-sessions/${baseline.id}`, 'DELETE')).status).toBe(200);
  expect((await previous(thursday)).status).toBe(404);
  history = await json('/workout-sessions');
  expect(history.total).toBe(1);
});

test('rename and duplicate names keep stable identity and omitted flags preserve opt-in', async () => {
  await toggle(thursday, true);
  await save(thursday, [set(40)]);
  expect((await patch([{ id: thursday, folderId, name: 'Lunes', position: 1 }])).status).toBe(200);
  expect((await json('/routine-library')).folders[0].routines[1].isolateResults).toBe(true);
  await save(monday, [set(80)]);
  expect((await values(thursday))[0].kg).toBe(40);
  expect((await values(monday))[0].kg).toBe(80);
  const newId = randomUUID();
  expect((await patch([{ id: newId, folderId, name: 'Jueves', position: 2, exercises: ['Press'], isolateResults: true }])).status).toBe(200);
  expect((await previous(newId)).status).toBe(404);
});

test('drafts retain identity, reject mid-workout changes and allow finishing a deleted isolated routine', async () => {
  await toggle(thursday, true);
  await save(thursday, [set(40)]);
  expect((await request('/workout-draft', 'PUT', draft(thursday))).status).toBe(200);
  expect(await json('/workout-draft')).toMatchObject({ routineId: thursday, isolateResults: true });
  const blocked = await patch([{ id: thursday, folderId, name: 'Jueves', position: 1, isolateResults: false }]);
  expect(blocked.status).toBe(409);
  expect((await blocked.json()).code).toBe('WORKOUT_IN_PROGRESS');
  await toggle(monday, true); // Another routine is allowed.
  expect((await patch([], [thursday])).status).toBe(200);
  expect((await values(thursday))[0].kg).toBe(40);
  await save(thursday, [set(60)]);
  expect((await values(thursday))[0].kg).toBe(60);
  expect((await previous()).status).toBe(404);
  expect((await request('/workout-draft', 'DELETE')).status).toBe(200);
});

test('foreign and invented routine identifiers cannot read, save or replace a draft', async () => {
  await toggle(thursday, true);
  for (const id of [thursday, randomUUID()]) {
    expect((await previous(id, bob)).status).toBe(404);
    expect((await request('/workout-draft', 'PUT', draft(id), bob)).status).toBe(404);
    const startedAt = new Date().toISOString();
    expect((await request('/workout-sessions', 'POST', { ...draft(id), startedAt, completedAt: startedAt, durationSeconds: 0 }, bob)).status).toBe(404);
  }
  expect((await previous(thursday, { ...alice, token: 'invalid' })).status).toBe(401);
});

test('old clients keep shared behavior but must reload before saving an isolated routine', async () => {
  const saved = await save(undefined, [set(50)], 'Lunes');
  expect((await db.select().from(workoutSessions).where(eq(workoutSessions.id, saved.id)))[0].routineId).toBe(monday);
  await toggle(thursday, true);
  const body = { ...draft(thursday), routineId: undefined };
  expect((await request('/workout-draft', 'PUT', body)).status).toBe(428);
  expect((await request('/workout-sessions', 'POST', { ...body, completedAt: body.startedAt, durationSeconds: 0 })).status).toBe(428);
});

test('concurrent saving and toggling leave session scope and references consistent', async () => {
  await save(monday, [set(80)]);
  await save(thursday, [set(40)]);
  await Promise.all([toggle(thursday, true), save(thursday, [set(50)])]);
  expect((await values(thursday))[0].kg).toBe(50);
  expect((await values())[0].kg).toBe(80);
  const sessions = await db.select().from(workoutSessions).where(eq(workoutSessions.routineId, thursday));
  expect(sessions.every(s => s.isolateResults)).toBe(true);
});

test('scoped references retain the existing replacement rule, set types and save ordering', async () => {
  await toggle(thursday, true);
  await save(thursday, [set(50, 10, 'warmup')]);
  await save(thursday, [set(60, 8)]);
  await save(thursday, [set(40, 12, 'failure')]);
  const winner = await save(thursday, [set(45, 9, 'drop')]);
  await save(thursday, [set(45, 9, 'normal')]);
  expect(await (await previous(thursday)).json()).toMatchObject({ completedAt: winner.completedAt, sets: [{ type: 'drop', kg: 45, reps: 9 }] });
});

test('sharing an isolated routine creates an independent copy without results or opt-in', async () => {
  await toggle(thursday, true);
  await save(thursday, [set(80)]);
  const { version } = await json('/routine-library');
  const id = randomUUID(), destination = randomUUID();
  const sent = await request('/routine-shares', 'POST', { id, routineId: thursday, recipientId: bob.id, version });
  expect(sent.status).toBe(200);
  const created = await request('/routine-library', 'PATCH', { version: 0, folders: [{ id: destination, name: 'Recibidas', position: 0 }],
    routines: [], deletedFolders: [], deletedRoutines: [] }, bob);
  expect(created.status).toBe(200);
  const accepted = await request(`/routine-shares/${id}/accept`, 'POST', { folderId: destination, version: 1 }, bob);
  expect(accepted.status).toBe(200);
  const imported = await (await request('/routine-library', 'GET', undefined, bob)).json();
  const copy = imported.folders[0].routines[0];
  expect(copy.id).not.toBe(thursday);
  expect(copy.isolateResults ?? false).toBe(false);
  expect((await previous(copy.id, bob)).status).toBe(404);
  expect((await values(thursday))[0].kg).toBe(80);
});

test('scoped references can seek series without scanning other accounts history', async () => {
  await toggle(thursday, true);
  await save(thursday, [set(40)]);
  await client`WITH sessions AS (
    INSERT INTO workout_sessions(user_id, routine_name, started_at, completed_at, duration_seconds)
    SELECT ${bob.id}, 'Otro', now(), now(), 0 FROM generate_series(1, 10000) RETURNING id
  ), exercise AS (
    INSERT INTO exercises(user_id, name, normalized_name) VALUES (${bob.id}, 'Press', 'press') RETURNING id
  ), links AS (
    INSERT INTO workout_session_exercises(session_id, exercise_id, position)
    SELECT s.id, e.id, 0 FROM sessions s CROSS JOIN exercise e RETURNING id
  ) INSERT INTO workout_sets(session_exercise_id, position, weight_kg, repetitions)
    SELECT id, 0, 80, 10 FROM links`;
  await client`ANALYZE workout_sessions`;
  await client`ANALYZE workout_session_exercises`;
  await client`ANALYZE workout_sets`;
  await client`ANALYZE exercises`;
  const plan = await client`EXPLAIN (FORMAT JSON) SELECT ws.weight_kg FROM exercises e
    JOIN workout_session_exercises se ON se.exercise_id = e.id
    JOIN workout_sessions s ON s.id = se.session_id
    JOIN workout_sets ws ON ws.session_exercise_id = se.id
    WHERE e.user_id = ${alice.id} AND e.normalized_name = 'press' AND s.user_id = ${alice.id}
      AND s.routine_id = ${thursday} AND s.isolate_results = true AND ws.completed = true`;
  expect(JSON.stringify(plan)).toContain('workout_sets_session_position_idx');
  expect((await values(thursday))[0].kg).toBe(40);
});

test('migration associates unique legacy names once per user and leaves ambiguous or reused names unassigned', async () => {
  const unique = await save(undefined, [set(40)], '  lunes  ');
  await patch([{ id: randomUUID(), folderId, name: 'Jueves', position: 2, exercises: ['Press'] }]);
  const ambiguous = await save(undefined, [set(60)], 'Jueves');
  const unmatched = await save(undefined, [set(70)], 'Sin rutina');
  const foreign = await save(undefined, [set(90)], 'Lunes', bob);
  await request('/workout-draft', 'PUT', { ...draft(monday), routineName: 'Lunes' });
  // Recreate the schema state from v31, then run the real startup migration.
  await client`ALTER TABLE workout_sessions DROP COLUMN routine_id, DROP COLUMN isolate_results`;
  await client`ALTER TABLE active_workout_drafts DROP COLUMN routine_id, DROP COLUMN isolate_results`;
  await client`ALTER TABLE routines DROP COLUMN isolate_results`;
  await migrateAuth(client);
  const rows = await db.select().from(workoutSessions);
  expect(rows.find(s => s.id === unique.id)?.routineId).toBe(monday);
  for (const id of [ambiguous.id, unmatched.id, foreign.id]) expect(rows.find(s => s.id === id)?.routineId).toBeNull();
  expect(await json('/workout-draft')).toMatchObject({ routineId: monday, isolateResults: false });
  await request('/workout-draft', 'DELETE');
  await patch([{ id: monday, folderId, name: 'Renombrado', position: 0 }, { id: randomUUID(), folderId, name: 'Sin rutina', position: 3 }]);
  await migrateAuth(client);
  const again = await db.select().from(workoutSessions);
  expect(again.find(s => s.id === unique.id)?.routineId).toBe(monday);
  expect(again.find(s => s.id === unmatched.id)?.routineId).toBeNull();
  await toggle(monday, true, 'Renombrado');
  expect((await values(monday))[0].kg).toBe(40);
});
