import { afterAll, beforeAll, beforeEach, expect, test } from 'bun:test';
import { randomBytes, randomUUID } from 'node:crypto';
import { asc, eq } from 'drizzle-orm';
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import { migrateAuth } from '../auth-migration.ts';
import { tokenHash } from '../auth.ts';
import { createApp } from '../index.ts';
import { authSessions, exerciseCatalog, exerciseRecords, exercises, users } from '../schema.ts';

const url = process.env.TEST_DATABASE_URL;
if (!url) throw new Error('Configura TEST_DATABASE_URL para probar en PostgreSQL.');
const schema = `hevy_catalog_test_${randomUUID().replaceAll('-', '')}`;
const admin = postgres(url, { max: 1, onnotice: () => {} });
const client = postgres(url, { max: 5, connection: { search_path: schema }, onnotice: () => {} });
const db = drizzle(client);
const accounts = ['alice', 'bob', 'carol'].map(name => ({ id: randomUUID(), name, token: randomBytes(32).toString('base64url') }));
const [alice, bob, carol] = accounts;
let app: ReturnType<typeof createApp>;
function request(path: string, user = alice, method = 'GET', body?: unknown) {
  return app.handle(new Request(`http://localhost${path}`, { method,
    headers: { authorization: `Bearer ${user.token}`, ...(body === undefined ? {} : { 'content-type': 'application/json' }) },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  }));
}
const catalog = async (user = alice) => (await request('/exercises', user)).json();
const workout = (name: string, kg: number, reps: number) => ({
  routineName: 'Entrenamiento', startedAt: '2026-10-23T10:00:00Z', completedAt: '2026-10-23T11:00:00Z', durationSeconds: 3600,
  exercises: [{ name, muscleGroup: 'Pecho', sets: [{ type: 'normal', kg, reps, completed: true }] }],
});
beforeAll(async () => { await admin`CREATE SCHEMA ${admin(schema)}`; await migrateAuth(client); });
beforeEach(async () => {
  await client`TRUNCATE exercise_catalog, users CASCADE`;
  for (const a of accounts) {
    await db.insert(users).values({ id: a.id, email: `${a.name}@gmail.com`, googleSubject: a.name, displayName: a.name });
    await db.insert(authSessions).values({ userId: a.id, tokenHash: tokenHash(a.token), expiresAt: new Date(Date.now() + 3600000) });
  }
  app = createApp(db, { clientId: 'test', clientSecret: 'test', webOrigin: 'https://app.i7l.cl', redirectUri: 'https://app.i7l.cl/api/auth/google/callback' });
});
afterAll(async () => { await client.end(); await admin`DROP SCHEMA ${admin(schema)} CASCADE`; await admin.end(); });

test('a created exercise is immediately visible to all accounts without importing personal data', async () => {
  const response = await request('/exercises', alice, 'POST', { name: '  Press inclinado  ', muscleGroup: ' Pecho ' });
  expect(response.status).toBe(201);
  expect(await response.json()).toEqual({ name: 'Press inclinado', muscleGroup: 'Pecho' });
  for (const user of [alice, bob, carol]) {
    expect(await catalog(user)).toEqual([{ name: 'Press inclinado', muscleGroup: 'Pecho' }]);
  }
  expect(await db.select().from(exercises).where(eq(exercises.userId, bob.id))).toHaveLength(0);
  expect((await request('/exercises/previous?name=Press%20inclinado', bob)).status).toBe(404);
  expect(await (await request('/exercises/rest-timer?name=Press%20inclinado', bob)).json()).toEqual({ restSeconds: 180 });
});

test('concurrent creation deduplicates case and spaces and keeps the original public description', async () => {
  const responses = await Promise.all([
    request('/exercises', alice, 'POST', { name: ' Press Inclinado ', muscleGroup: 'Pecho' }),
    request('/exercises', bob, 'POST', { name: 'press inclinado', muscleGroup: 'Otro' }),
  ]);
  expect(responses.map(r => r.status)).toEqual([201, 201]);
  const descriptions = await Promise.all(responses.map(r => r.json()));
  expect(descriptions[0]).toEqual(descriptions[1]);
  expect(await catalog(carol)).toEqual([descriptions[0]]);
  expect(await db.select().from(exercises)).toHaveLength(2);
  const again = await request('/exercises', carol, 'POST', { name: 'PRESS INCLINADO', muscleGroup: 'Hombros' });
  expect(await again.json()).toEqual(descriptions[0]);
  expect(await catalog()).toEqual([descriptions[0]]);
});

test('reusing a global exercise keeps each account history, records and rest independent', async () => {
  expect((await request('/workout-sessions', alice, 'POST', workout('Press', 80, 10))).status).toBe(201);
  expect((await request('/exercises/rest-timer', alice, 'PUT', { name: 'Press', restSeconds: 120 })).status).toBe(200);
  expect(await catalog(bob)).toEqual([{ name: 'Press', muscleGroup: 'Pecho' }]);
  expect((await request('/exercises/previous?name=Press', bob)).status).toBe(404);
  expect((await request('/workout-sessions', bob, 'POST', workout('Press', 30, 6))).status).toBe(201);
  expect((await request('/exercises/rest-timer', bob, 'PUT', { name: 'Press', restSeconds: 240 })).status).toBe(200);
  for (const [user, kg, reps, restSeconds] of [[alice, 80, 10, 120], [bob, 30, 6, 240]] as const) {
    const previous = await (await request('/exercises/previous?name=Press', user)).json();
    expect(previous.sets).toMatchObject([{ kg, reps }]);
    expect(await (await request('/exercises/rest-timer?name=Press', user)).json()).toEqual({ restSeconds });
    const history = await (await request('/workout-sessions', user)).json();
    expect(history.total).toBe(1);
    expect(history.sessions[0].volumeKg).toBe(kg * reps);
  }
  const privateExercises = await db.select().from(exercises);
  expect(new Set(privateExercises.map(e => e.id)).size).toBe(2);
  expect(await db.select().from(exerciseCatalog)).toHaveLength(1);
  expect(await db.select().from(exerciseRecords)).toHaveLength(2);
});

test('upgrade publishes existing exercises without changing private IDs, history or preferences', async () => {
  await request('/workout-sessions', alice, 'POST', workout('Press', 80, 10));
  await request('/exercises/rest-timer', alice, 'PUT', { name: 'Press', restSeconds: 90 });
  await db.insert(exercises).values([
    { userId: bob.id, name: 'press', normalizedName: 'press', muscleGroup: null },
    { userId: bob.id, name: 'Remo', normalizedName: 'remo', muscleGroup: 'Espalda' },
  ]);
  const privateBefore = await db.select().from(exercises).orderBy(asc(exercises.id));
  const recordsBefore = await db.select().from(exerciseRecords);
  const historyBefore = await (await request('/workout-sessions')).json();
  await client`DROP TABLE exercise_catalog`;
  await migrateAuth(client);
  const publicBefore = await db.select().from(exerciseCatalog).orderBy(asc(exerciseCatalog.id));
  await migrateAuth(client);
  expect(await db.select().from(exerciseCatalog).orderBy(asc(exerciseCatalog.id))).toEqual(publicBefore);
  expect((await catalog(carol)).sort((a: { name: string }, b: { name: string }) => a.name.localeCompare(b.name))).toEqual([
    { name: 'Press', muscleGroup: 'Pecho' }, { name: 'Remo', muscleGroup: 'Espalda' },
  ]);
  expect(await db.select().from(exercises).orderBy(asc(exercises.id))).toEqual(privateBefore);
  expect(await db.select().from(exerciseRecords)).toEqual(recordsBefore);
  expect(await (await request('/workout-sessions')).json()).toEqual(historyBefore);
  expect(await (await request('/exercises/rest-timer?name=Press')).json()).toEqual({ restSeconds: 90 });
});

test('rest-only entries gain a classification once without later users overwriting it', async () => {
  await request('/exercises/rest-timer', alice, 'PUT', { name: 'Remo', restSeconds: 60 });
  expect(await catalog(bob)).toEqual([{ name: 'Remo', muscleGroup: null }]);
  await request('/exercises', bob, 'POST', { name: 'remo', muscleGroup: 'Espalda' });
  expect(await catalog()).toEqual([{ name: 'Remo', muscleGroup: 'Espalda' }]);
  await request('/exercises', carol, 'POST', { name: 'Remo', muscleGroup: 'Otro' });
  expect(await catalog()).toEqual([{ name: 'Remo', muscleGroup: 'Espalda' }]);
  expect(await (await request('/exercises/rest-timer?name=Remo')).json()).toEqual({ restSeconds: 60 });
});

test('empty descriptions are rejected and deleting the creator keeps the shared exercise', async () => {
  for (const body of [{ name: ' ', muscleGroup: 'Pecho' }, { name: 'Press', muscleGroup: ' ' }]) {
    expect((await request('/exercises', alice, 'POST', body)).status).toBe(400);
  }
  expect(await catalog()).toEqual([]);
  expect(await db.select().from(exercises)).toHaveLength(0);
  await request('/exercises', alice, 'POST', { name: 'Press', muscleGroup: 'Pecho' });
  await db.delete(users).where(eq(users.id, alice.id));
  expect(await catalog(bob)).toEqual([{ name: 'Press', muscleGroup: 'Pecho' }]);
});
