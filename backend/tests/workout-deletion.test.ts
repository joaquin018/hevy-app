import { afterAll, beforeAll, beforeEach, expect, test } from 'bun:test';
import { randomBytes, randomUUID } from 'node:crypto';
import { eq } from 'drizzle-orm';
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import { migrateAuth } from '../auth-migration.ts';
import { tokenHash } from '../auth.ts';
import { createApp } from '../index.ts';
import { authSessions, exerciseRecords, exercises, users, workoutSessionExercises, workoutSets } from '../schema.ts';

const url = process.env.TEST_DATABASE_URL;
if (!url) throw new Error('Configura TEST_DATABASE_URL para probar en PostgreSQL.');
const schema = `hevy_delete_test_${randomUUID().replaceAll('-', '')}`;
const admin = postgres(url, { max: 1, onnotice: () => {} });
const client = postgres(url, { max: 5, connection: { search_path: schema }, onnotice: () => {} });
const db = drizzle(client);
const [alice, bob] = ['alice', 'bob'].map(name => ({ id: randomUUID(), name, token: randomBytes(32).toString('base64url') }));
let app: ReturnType<typeof createApp>;
let workoutNumber = 0;
function request(path: string, user = alice, method = 'GET', body?: unknown, headers: Record<string, string> = {}) {
  return app.handle(new Request(`http://localhost${path}`, { method,
    headers: { authorization: `Bearer ${user.token}`, ...headers, ...(body === undefined ? {} : { 'content-type': 'application/json' }) },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }));
}
const set = (kg: number, reps = 10, type = 'normal') => ({ type, kg, reps, completed: true });
const press = (kg: number, reps = 10, type = 'normal') => ({ name: 'Press', sets: [set(kg, reps, type)] });
async function save(entries: { name: string; sets: ReturnType<typeof set>[] }[], user = alice) {
  const startedAt = new Date(Date.UTC(2026, 9, 1 + workoutNumber++, 10));
  const response = await request('/workout-sessions', user, 'POST', {
    routineName: 'Empuje', startedAt: startedAt.toISOString(),
    completedAt: new Date(startedAt.getTime() + 3600000).toISOString(), durationSeconds: 3600, exercises: entries,
  });
  expect(response.status).toBe(201);
  return await response.json() as { id: string; completedAt: string };
}
const history = async (user = alice) => (await request('/workout-sessions', user)).json();
const previous = async (user = alice) => (await request('/exercises/previous?name=Press', user)).json();
const remove = (id: string, user = alice) => request(`/workout-sessions/${id}`, user, 'DELETE');

beforeAll(async () => { await admin`CREATE SCHEMA ${admin(schema)}`; await migrateAuth(client); });
beforeEach(async () => {
  await client`TRUNCATE exercise_catalog, users CASCADE`;
  workoutNumber = 0;
  for (const a of [alice, bob]) {
    await db.insert(users).values({ id: a.id, displayName: a.name, email: `${a.name}@gmail.com`, googleSubject: a.name });
    await db.insert(authSessions).values({ userId: a.id, tokenHash: tokenHash(a.token), expiresAt: new Date(Date.now() + 3600000) });
  }
  app = createApp(db, { clientId: 'test', clientSecret: 'test', webOrigin: 'https://app.i7l.cl', redirectUri: 'https://app.i7l.cl/api/auth/google/callback' });
});
afterAll(async () => { await client.end(); await admin`DROP SCHEMA ${admin(schema)} CASCADE`; await admin.end(); });

test('only the owner can delete; anonymous, cross-origin and stale-account requests fail', async () => {
  const own = await save([press(50)]);
  const foreign = await save([press(80)], bob);
  expect((await remove(own.id, { ...alice, token: 'invalid' })).status).toBe(401);
  expect((await request(`/workout-sessions/${own.id}`, alice, 'DELETE', undefined, { origin: 'https://other.example.com' })).status).toBe(403);
  expect((await request(`/workout-sessions/${own.id}`, alice, 'DELETE', undefined, { 'x-i7l-user': bob.id })).status).toBe(409);
  const hidden = await remove(foreign.id);
  const missing = await remove(randomUUID());
  expect(hidden.status).toBe(404);
  expect(missing.status).toBe(404);
  expect(await hidden.json()).toEqual(await missing.json());
  expect((await request('/workout-sessions/not-a-uuid', alice, 'DELETE')).status).toBe(422);
  expect((await history()).total).toBe(1);
  expect((await history(bob)).total).toBe(1);
  expect((await remove(own.id)).status).toBe(200);
  expect((await remove(own.id)).status).toBe(404);
  expect((await history(bob)).total).toBe(1);
  expect((await previous(bob)).sets[0].kg).toBe(80);
});

test('deleting a mistaken best restores set values, types and dates and cascades only its series', async () => {
  const baseline = await save([{ name: 'Press', sets: [set(22, 12, 'warmup'), set(58, 9), set(58, 5)] }]);
  const wrong = await save([{ name: 'Press', sets: [set(220, 20), set(580, 20), set(580, 20), set(500, 20, 'failure')] }]);
  await save([{ name: 'Remo', sets: [set(40)] }]);
  const [unaffected] = await db.select({ record: exerciseRecords }).from(exerciseRecords)
    .innerJoin(exercises, eq(exercises.id, exerciseRecords.exerciseId)).where(eq(exercises.name, 'Remo'));
  const deletedLinks = await db.select().from(workoutSessionExercises).where(eq(workoutSessionExercises.sessionId, wrong.id));
  expect(await (await remove(wrong.id)).json()).toEqual({ deleted: true });
  expect((await previous()).sets).toEqual([
    { position: 0, type: 'warmup', kg: 22, reps: 12 },
    { position: 1, type: 'normal', kg: 58, reps: 9 },
    { position: 2, type: 'normal', kg: 58, reps: 5 },
  ]);
  expect((await previous()).completedAt).toBe(baseline.completedAt);
  expect(await db.select().from(workoutSessionExercises).where(eq(workoutSessionExercises.sessionId, wrong.id))).toHaveLength(0);
  for (const link of deletedLinks) expect(await db.select().from(workoutSets).where(eq(workoutSets.sessionExerciseId, link.id))).toHaveLength(0);
  expect((await db.select().from(exerciseRecords).where(eq(exerciseRecords.id, unaffected.record.id)))[0]).toEqual(unaffected.record);
  expect((await history()).sessions.map((s: { id: string }) => s.id)).not.toContain(wrong.id);
  expect((await history()).total).toBe(2);
});

test('deleting an incorrect first reference recalculates later badges and paginated totals', async () => {
  const wrong = await save([press(100)]);
  const baseline = await save([press(50)]);
  const improvement = await save([press(60)]);
  expect((await history()).sessions.every((s: { records: number }) => s.records === 0)).toBe(true);
  await remove(wrong.id);
  const updated = await history();
  expect(updated.sessions.map((s: { id: string; records: number }) => [s.id, s.records])).toEqual([[improvement.id, 1], [baseline.id, 0]]);
  const page = await (await request('/workout-sessions?offset=1&limit=1')).json();
  expect(page.total).toBe(2);
  expect(page.hasMore).toBe(false);
  expect(page.sessions.map((s: { id: string }) => s.id)).toEqual([baseline.id]);
  expect((await previous()).sets[0].kg).toBe(60);
});

test('rebuilding follows higher weight OR reps in save order and retains the original type on ties', async () => {
  await save([press(50, 10, 'warmup')]);
  await save([press(60, 8)]);
  await save([press(40, 12, 'failure')]);
  const winner = await save([press(45, 9, 'drop')]);
  await save([press(45, 9, 'warmup')]);
  const wrong = await save([press(1000, 100)]);
  await remove(wrong.id);
  expect(await previous()).toMatchObject({ completedAt: winner.completedAt, sets: [{ position: 0, type: 'drop', kg: 45, reps: 9 }] });
});

test('deleting the last session clears records but keeps routines, drafts, rest preferences and the catalog', async () => {
  const folderId = randomUUID(), routineId = randomUUID();
  await request('/routine-library', alice, 'PATCH', { version: 0,
    folders: [{ id: folderId, name: 'Plan', position: 0 }], deletedFolders: [], deletedRoutines: [],
    routines: [{ id: routineId, folderId, name: 'Empuje', position: 0, exercises: ['Press'] }],
  });
  const routineBefore = await (await request('/routine-library')).json();
  const saved = await save([press(50)]);
  await request('/exercises/rest-timer', alice, 'PUT', { name: 'Press', restSeconds: 90 });
  await request('/workout-draft', alice, 'PUT', { routineName: 'En curso', startedAt: '2026-10-26T10:00:00Z', originalExercises: ['Press'], exercises: [] });
  await save([press(80)], bob);
  expect((await remove(saved.id)).status).toBe(200);
  expect(await history()).toMatchObject({ total: 0, sessions: [], hasMore: false });
  expect((await request('/exercises/previous?name=Press')).status).toBe(404);
  expect(await (await request('/exercises/rest-timer?name=Press')).json()).toEqual({ restSeconds: 90 });
  expect(await (await request('/routine-library')).json()).toEqual(routineBefore);
  expect(await (await request('/workout-draft')).json()).toMatchObject({ routineName: 'En curso' });
  expect(await (await request('/exercises')).json()).toHaveLength(1);
  expect((await previous(bob)).sets[0].kg).toBe(80);
});

test('a session without completed exercises can be deleted', async () => {
  const empty = await save([]);
  expect((await remove(empty.id)).status).toBe(200);
  expect((await history()).total).toBe(0);
});

test('concurrent save/delete and duplicate deletes cannot leave stale record references', async () => {
  const baseline = await save([press(50)]);
  const wrong = await save([press(100)]);
  const [deleted] = await Promise.all([remove(wrong.id), save([press(70)])]);
  expect(deleted.status).toBe(200);
  expect((await previous()).sets[0].kg).toBe(70);
  expect((await history()).total).toBe(2);
  const duplicates = await Promise.all([remove(baseline.id), remove(baseline.id)]);
  expect(duplicates.map(r => r.status).sort()).toEqual([200, 404]);
  expect((await previous()).sets[0].kg).toBe(70);
});

test('concurrent retries still save a workout exactly once', async () => {
  const body = { routineName: 'Empuje', startedAt: '2026-10-26T10:00:00Z', completedAt: '2026-10-26T11:00:00Z',
    durationSeconds: 3600, exercises: [press(50)] };
  const responses = await Promise.all([
    request('/workout-sessions', alice, 'POST', body), request('/workout-sessions', alice, 'POST', body),
  ]);
  expect(responses.map(r => r.status)).toEqual([201, 201]);
  const saved = await Promise.all(responses.map(r => r.json()));
  expect(saved[0].id).toBe(saved[1].id);
  expect((await history()).total).toBe(1);
  expect(await db.select().from(workoutSets)).toHaveLength(1);
});

test('a failed record rebuild rolls back the deletion and its cascading changes', async () => {
  await save([press(40)]);
  const wrong = await save([press(100)]);
  const historyBefore = await history();
  const previousBefore = await previous();
  await client`CREATE FUNCTION reject_record_insert() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Test record rebuild failure'; END; $$`;
  await client`CREATE TRIGGER reject_record_insert BEFORE INSERT ON exercise_records FOR EACH ROW EXECUTE FUNCTION reject_record_insert()`;
  try {
    expect((await remove(wrong.id)).status).toBe(500);
    expect(await history()).toEqual(historyBefore);
    expect(await previous()).toEqual(previousBefore);
  } finally {
    await client`DROP TRIGGER reject_record_insert ON exercise_records`;
    await client`DROP FUNCTION reject_record_insert()`;
  }
});
