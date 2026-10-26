import { Elysia, t } from 'elysia';
import { and, asc, desc, eq, sql } from 'drizzle-orm';
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import { buildWorkoutHistory } from './workout-history.ts';
import { authenticate, authRoutes, requestAuthorization, rejectCrossOrigin, validateAuthConfig, type Database, type AuthConfig, type GoogleProvider } from './auth.ts';
import { migrateAuth } from './auth-migration.ts';
import { RoutineError, RoutineLibrary } from './routine-library.ts';
import { publishExercises } from './exercise-catalog.ts';
import { lockWorkoutWrites, readRoutineReferences, rebuildExerciseRecords } from './workout-records.ts';
import { resolveRoutineContext } from './routine-results.ts';

import {
  activeWorkoutDrafts,
  exerciseCatalog,
  exercises,
  exerciseRecords,
  workoutSessionExercises,
  workoutSessions,
  workoutSets,
  users,
} from './schema.ts';

const port = Number(process.env.PORT ?? 3000);
const databaseUrl = process.env.DATABASE_URL ??
  'postgres://hevy:hevy_dev_password@localhost:5432/hevy';
export function createApp(db: Database, config: AuthConfig, provider?: GoogleProvider) {
validateAuthConfig(config);
const library = new RoutineLibrary(db);
const app = new Elysia().onError(({ code, error, set }) => {
  if (error instanceof RoutineError) {
    set.status = error.status;
    return { code: error.code, message: error.message };
  }
  if (code === 'UNKNOWN') {
    console.error('Unhandled API error:', error.name);
    set.status = 500;
    return { message: 'No se pudo completar la acción. Inténtalo de nuevo.' };
  }
}).onRequest(({ request, status, set }) => {
  set.headers['cache-control'] = 'no-store';
  if (rejectCrossOrigin(request, config)) return status(403, { message: 'Origen no permitido.' });
}).use(authRoutes(db, config, provider)).resolve(async ({ headers, status }) => {
  const user = await authenticate(db, requestAuthorization(headers), config.skipLogin);
  if (!user) return status(401, { message: 'Inicia sesión para continuar.' });
  // A cookie can change in another tab while this tab still displays the old account.
  if (headers['x-i7l-user'] && headers['x-i7l-user'] !== user.id) {
    return status(409, { code: 'SESSION_CHANGED', message: 'La cuenta cambió. Vuelve a iniciar sesión.' });
  }
  return { userId: user.id };
});

const normalizeName = (name: string) => name.trim().toLocaleLowerCase('es');


app.get('/workout-sessions', async ({ query, userId }) => {
  const offset = query.offset ?? 0;
  const limit = query.limit ?? 20;
  return db.transaction(async (tx) => {
    const sessions = await tx.select().from(workoutSessions)
      .where(eq(workoutSessions.userId, userId))
      .orderBy(asc(workoutSessions.createdAt), asc(workoutSessions.id));
    const rows = await tx.select({
      sessionId: workoutSessionExercises.sessionId,
      sessionExerciseId: workoutSessionExercises.id,
      exerciseId: exercises.id,
      name: exercises.name,
      position: workoutSets.position,
      type: workoutSets.setType,
      kg: workoutSets.weightKg,
      reps: workoutSets.repetitions,
    }).from(workoutSessions)
      .innerJoin(workoutSessionExercises, eq(workoutSessionExercises.sessionId, workoutSessions.id))
      .innerJoin(exercises, eq(exercises.id, workoutSessionExercises.exerciseId))
      .innerJoin(workoutSets, eq(workoutSets.sessionExerciseId, workoutSessionExercises.id))
      .where(and(eq(workoutSessions.userId, userId), eq(workoutSets.completed, true)))
      .orderBy(asc(workoutSessions.createdAt), asc(workoutSessions.id), asc(workoutSessionExercises.position), asc(workoutSets.position));
    const history = buildWorkoutHistory(sessions, rows);
    return { sessions: history.slice(offset, offset + limit), total: history.length, hasMore: offset + limit < history.length };
  }, { isolationLevel: 'repeatable read', accessMode: 'read only' });
}, {
  query: t.Object({
    offset: t.Optional(t.Numeric({ minimum: 0, maximum: 1000000, multipleOf: 1 })),
    limit: t.Optional(t.Numeric({ minimum: 1, maximum: 100, multipleOf: 1 })),
  }),
});

app.get('/workout-draft', async ({ set, userId }) => {
  const [draft] = await db
    .select()
    .from(activeWorkoutDrafts)
    .where(eq(activeWorkoutDrafts.userId, userId))
    .limit(1);
  if (!draft) {
    set.status = 404;
    return { message: 'No hay un entrenamiento en curso' };
  }
  return draft;
});

app.delete('/workout-sessions/:id', async ({ params, userId }) => {
  return db.transaction(async (tx) => {
    await lockWorkoutWrites(tx, userId);
    const [session] = await tx.select({ id: workoutSessions.id }).from(workoutSessions)
      .where(and(eq(workoutSessions.id, params.id), eq(workoutSessions.userId, userId)));
    if (!session) throw new RoutineError(404, 'WORKOUT_NOT_FOUND', 'No se encontró el entrenamiento.');
    const affected = await tx.select({ exerciseId: workoutSessionExercises.exerciseId }).from(workoutSessionExercises)
      .where(eq(workoutSessionExercises.sessionId, session.id));
    // Foreign keys remove only this session's exercises and sets. The private
    // exercise settings and the global catalog remain available for reuse.
    await tx.delete(workoutSessions).where(and(eq(workoutSessions.id, session.id), eq(workoutSessions.userId, userId)));
    await rebuildExerciseRecords(tx, userId, [...new Set(affected.map(row => row.exerciseId))]);
    return { deleted: true };
  });
}, { params: t.Object({ id: t.String({ format: 'uuid' }) }) });

app.put(
  '/workout-draft',
  async ({ body, userId }) => {
    await db.transaction(async (tx) => {
      await lockWorkoutWrites(tx, userId);
      const routine = await resolveRoutineContext(tx, userId, body);
      await tx
        .insert(activeWorkoutDrafts)
        .values({
          userId: userId,
          routineName: body.routineName,
          ...routine,
          startedAt: new Date(body.startedAt),
          originalExercises: body.originalExercises,
          exercises: body.exercises,
          updatedAt: new Date(),
        })
        .onConflictDoUpdate({
          target: activeWorkoutDrafts.userId,
          set: {
            routineName: body.routineName,
            ...routine,
            startedAt: new Date(body.startedAt),
            originalExercises: body.originalExercises,
            exercises: body.exercises,
            updatedAt: new Date(),
          },
        });
    });
    return { saved: true };
  },
  {
    body: t.Object({
      routineName: t.String({ minLength: 1, maxLength: 120 }),
      routineId: t.Optional(t.String({ format: 'uuid' })),
      startedAt: t.String({ format: 'date-time' }),
      originalExercises: t.Array(t.String({ minLength: 1, maxLength: 160 })),
      exercises: t.Array(
        t.Object({
          name: t.String({ minLength: 1, maxLength: 160 }),
          sets: t.Array(
            t.Object({
              type: t.Union([
                t.Literal('warmup'),
                t.Literal('normal'),
                t.Literal('failure'),
                t.Literal('drop'),
              ]),
              kg: t.Number({ minimum: 0 }),
              reps: t.Integer({ minimum: 0 }),
              completed: t.Boolean(),
              kgInput: t.Optional(t.String({ maxLength: 30 })),
              repsInput: t.Optional(t.String({ maxLength: 30 })),
            }),
          ),
        }),
      ),
    }),
  },
);

app.delete('/workout-draft', async ({ userId }) => {
  await db
    .delete(activeWorkoutDrafts)
    .where(eq(activeWorkoutDrafts.userId, userId));
  return { deleted: true };
});

app.get('/exercises', async () => {
  return db
    .select({ name: exerciseCatalog.name, muscleGroup: exerciseCatalog.muscleGroup })
    .from(exerciseCatalog)
    .orderBy(desc(exerciseCatalog.createdAt), asc(exerciseCatalog.name));
});

app.post(
  '/exercises',
  async ({ body, set, userId }) => {
    const name = body.name.trim(), muscleGroup = body.muscleGroup.trim();
    if (!name || !muscleGroup) throw new RoutineError(400, 'INVALID_EXERCISE', 'Escribe el nombre y el grupo muscular del ejercicio.');
    const exercise = await db.transaction(async (tx) => {
      await tx
        .insert(exercises)
        .values({
          userId: userId,
          name,
          normalizedName: normalizeName(name),
          muscleGroup,
        })
        .onConflictDoUpdate({
          target: [exercises.userId, exercises.normalizedName],
          set: {
            name,
            muscleGroup,
          },
        });
      await publishExercises(tx, [{ name, muscleGroup }]);
      const [entry] = await tx.select({ name: exerciseCatalog.name, muscleGroup: exerciseCatalog.muscleGroup })
        .from(exerciseCatalog).where(eq(exerciseCatalog.normalizedName, normalizeName(name)));
      return entry;
    });
    set.status = 201;
    return exercise;
  },
  {
    body: t.Object({
      name: t.String({ minLength: 1, maxLength: 160 }),
      muscleGroup: t.String({ minLength: 1, maxLength: 100 }),
    }),
  },
);

// Compatibility for v34 clients. Current clients use the routine-scoped route.
app.get('/workout-settings', async ({ userId }) => {
  const [settings] = await db.select({ betweenExercisesSeconds: users.betweenExercisesSeconds })
    .from(users).where(eq(users.id, userId));
  return settings;
});
app.put('/workout-settings', async ({ body, userId }) => {
  const [settings] = await db.update(users).set({ betweenExercisesSeconds: body.betweenExercisesSeconds })
    .where(eq(users.id, userId)).returning({ betweenExercisesSeconds: users.betweenExercisesSeconds });
  return settings;
}, { body: t.Object({ betweenExercisesSeconds: t.Integer({ minimum: 60, maximum: 300, multipleOf: 30 }) }) });

app.get(
  '/exercises/rest-timer',
  async ({ query, userId }) => {
    const [exercise] = await db
      .select({ restSeconds: exercises.restSeconds })
      .from(exercises)
      .where(
        and(
          eq(exercises.userId, userId),
          eq(exercises.normalizedName, normalizeName(query.name)),
        ),
      )
      .limit(1);
    return { restSeconds: exercise?.restSeconds ?? 180 };
  },
  {
    query: t.Object({ name: t.String({ minLength: 1, maxLength: 160 }) }),
  },
);

app.put(
  '/exercises/rest-timer',
  async ({ body, userId }) => {
    const exercise = await db.transaction(async (tx) => {
      const [saved] = await tx
        .insert(exercises)
        .values({
          userId: userId,
          name: body.name.trim(),
          normalizedName: normalizeName(body.name),
          restSeconds: body.restSeconds,
        })
        .onConflictDoUpdate({
          target: [exercises.userId, exercises.normalizedName],
          set: { restSeconds: body.restSeconds },
        })
        .returning({ restSeconds: exercises.restSeconds });
      await publishExercises(tx, [{ name: body.name }]);
      return saved;
    });
    return exercise;
  },
  {
    body: t.Object({
      name: t.String({ minLength: 1, maxLength: 160 }),
      restSeconds: t.Integer({ minimum: 60, maximum: 300 }),
    }),
  },
);

const uuid = () => t.String({ format: 'uuid' });
const position = () => t.Integer({ minimum: 0, maximum: 1000000 });
app.get('/routines/:id/rest-timer', ({ userId, params }) => library.restTimer(userId, params.id), {
  params: t.Object({ id: uuid() }),
});
app.put('/routines/:id/rest-timer', ({ userId, params, body }) => library.saveRestTimer(userId, params.id, body.betweenExercisesSeconds), {
  params: t.Object({ id: uuid() }),
  body: t.Object({ betweenExercisesSeconds: t.Integer({ minimum: 60, maximum: 300, multipleOf: 30 }) }),
});
app.get('/routine-library', ({ userId }) => library.read(userId));
// Older tabs can read, but must reload before saving without a revision.
app.get('/routine-folders', async ({ userId }) => {
  const value = await library.read(userId);
  return value.folders.map(folder => ({ name: folder.name,
    routines: folder.routines.map(routine => ({ name: routine.name, exercises: routine.exercises })) }));
});
app.put('/routine-folders', ({ status }) => status(428, {
  code: 'ROUTINE_UPGRADE_REQUIRED', message: 'Recarga la app para guardar tus rutinas con la nueva versión.'
}));
app.patch('/routine-library', ({ userId, body }) => library.patch(userId, body), {
  body: t.Object({
    version: t.Integer({ minimum: 0 }),
    folders: t.Array(t.Object({ id: uuid(), name: t.String({ minLength: 1, maxLength: 120 }), position: position() }), { maxItems: 100 }),
    deletedFolders: t.Array(uuid(), { maxItems: 100 }),
    routines: t.Array(t.Object({ id: uuid(), folderId: uuid(), name: t.String({ minLength: 1, maxLength: 120 }), position: position(),
      isolateResults: t.Optional(t.Boolean()),
      exercises: t.Optional(t.Array(t.String({ minLength: 1, maxLength: 160 }), { maxItems: 100 })) }), { maxItems: 500 }),
    deletedRoutines: t.Array(uuid(), { maxItems: 500 }),
  }),
});
app.get('/routine-recipients', ({ userId, query }) => library.recipients(userId, query.q), {
  query: t.Object({ q: t.String({ maxLength: 254 }) }),
});
app.post('/routine-shares', ({ userId, body }) => library.send(userId, body), {
  body: t.Object({ id: uuid(), routineId: uuid(), recipientId: uuid(), version: t.Integer({ minimum: 0 }) }),
});
app.post('/folder-shares', ({ userId, body }) => library.send(userId, body), {
  body: t.Object({ id: uuid(), folderId: uuid(), recipientId: uuid(), version: t.Integer({ minimum: 0 }) }),
});
app.get('/routine-shares/pending', ({ userId, query }) => library.hasPending(userId, query.includeFolders === 'true'), {
  query: t.Object({ includeFolders: t.Optional(t.Literal('true')) }),
});
app.get('/routine-shares', ({ userId, query }) => library.list(userId, query.direction ?? 'received', query.cursor, query.includeFolders === 'true'), {
  query: t.Object({ direction: t.Optional(t.Union([t.Literal('received'), t.Literal('sent')])), cursor: t.Optional(t.String({ maxLength: 300 })), includeFolders: t.Optional(t.Literal('true')) }),
});
app.get('/routine-shares/:id', ({ userId, params }) => library.detail(userId, params.id), { params: t.Object({ id: uuid() }) });
app.post('/routine-shares/:id/accept', ({ userId, params, body }) => library.accept(userId, params.id, body.folderId), {
  params: t.Object({ id: uuid() }), body: t.Object({ folderId: t.Optional(uuid()) }),
});
app.post('/routine-shares/:id/reject', ({ userId, params }) => library.resolve(userId, params.id, 'reject'), { params: t.Object({ id: uuid() }) });
app.post('/routine-shares/:id/revoke', ({ userId, params }) => library.resolve(userId, params.id, 'revoke'), { params: t.Object({ id: uuid() }) });

app.post(
  '/workout-sessions',
  async ({ body, set, userId }) => {
    const created = await db.transaction(async (tx) => {

      await lockWorkoutWrites(tx, userId);
      const [existing] = await tx.select().from(workoutSessions).where(and(
        eq(workoutSessions.userId, userId), eq(workoutSessions.startedAt, new Date(body.startedAt)),
      )).limit(1);
      if (existing) return existing;
      const routine = await resolveRoutineContext(tx, userId, body);

      const [session] = await tx
        .insert(workoutSessions)
        .values({
          userId: userId,
          routineName: body.routineName,
          ...routine,
          startedAt: new Date(body.startedAt),
          completedAt: new Date(body.completedAt),
          durationSeconds: body.durationSeconds,
          // Stamp after acquiring the lock so replay follows the save order.
          createdAt: sql`clock_timestamp()`,
        })
        .returning();

      const catalogEntries: { name: string; muscleGroup: string | null }[] = [];
      for (const [exercisePosition, inputExercise] of body.exercises.entries()) {
        const completedSets = inputExercise.sets
          .map((workoutSet, position) => ({ workoutSet, position }))
          .filter(({ workoutSet }) => workoutSet.completed);
        if (completedSets.length === 0) continue;

        const normalizedName = normalizeName(inputExercise.name);
        const [exercise] = await tx
          .insert(exercises)
          .values({
            userId: userId,
            name: inputExercise.name.trim(),
            normalizedName,
            muscleGroup: inputExercise.muscleGroup,
          })
          .onConflictDoUpdate({
            target: [exercises.userId, exercises.normalizedName],
            set: {
              name: inputExercise.name.trim(),
              muscleGroup: inputExercise.muscleGroup,
            },
          })
          .returning();

        catalogEntries.push({ name: exercise.name, muscleGroup: exercise.muscleGroup });

        const [sessionExercise] = await tx
          .insert(workoutSessionExercises)
          .values({
            sessionId: session.id,
            exerciseId: exercise.id,
            position: exercisePosition,
          })
          .returning();

        await tx.insert(workoutSets).values(
          completedSets.map(({ workoutSet, position }) => ({
              sessionExerciseId: sessionExercise.id,
              position,
              setType: workoutSet.type,
              weightKg: String(workoutSet.kg),
              repetitions: workoutSet.reps,
              completed: workoutSet.completed,
          })),
        );

        if (session.isolateResults) continue;
        for (const { workoutSet, position } of completedSets) {
          const [record] = await tx
            .select()
            .from(exerciseRecords)
            .where(
              and(
                eq(exerciseRecords.exerciseId, exercise.id),
                eq(exerciseRecords.position, position),
              ),
            )
            .limit(1);
          const breaksRecord =
            !record ||
            workoutSet.kg > Number(record.weightKg) ||
            workoutSet.reps > record.repetitions;
          if (!breaksRecord) continue;

          if (record) {
            await tx
              .update(exerciseRecords)
              .set({
                setType: workoutSet.type,
                weightKg: String(workoutSet.kg),
                repetitions: workoutSet.reps,
                achievedAt: new Date(body.completedAt),
              })
              .where(eq(exerciseRecords.id, record.id));
          } else {
            await tx.insert(exerciseRecords).values({
              exerciseId: exercise.id,
              position,
              setType: workoutSet.type,
              weightKg: String(workoutSet.kg),
              repetitions: workoutSet.reps,
              achievedAt: new Date(body.completedAt),
            });
          }
        }
      }

      await publishExercises(tx, catalogEntries);
      return session;
    });

    set.status = 201;
    return created;
  },
  {
    body: t.Object({
      routineName: t.Optional(t.String({ maxLength: 120 })),
      routineId: t.Optional(t.String({ format: 'uuid' })),
      startedAt: t.String({ format: 'date-time' }),
      completedAt: t.String({ format: 'date-time' }),
      durationSeconds: t.Integer({ minimum: 0 }),
      exercises: t.Array(
        t.Object({
          name: t.String({ minLength: 1, maxLength: 160 }),
          muscleGroup: t.Optional(t.String({ maxLength: 100 })),
          sets: t.Array(
            t.Object({
              type: t.Union([
                t.Literal('warmup'),
                t.Literal('normal'),
                t.Literal('failure'),
                t.Literal('drop'),
              ]),
              kg: t.Number({ minimum: 0 }),
              reps: t.Integer({ minimum: 0 }),
              completed: t.Boolean(),
            }),
          ),
        }),
      ),
    }),
  },
);

app.get(
  '/exercises/previous',
  async ({ query, set, userId }) => {
    return db.transaction(async (tx) => {
      const routine = await resolveRoutineContext(tx, userId, { routineId: query.routineId });
      const records = routine.isolateResults && routine.routineId
        ? (await readRoutineReferences(tx, userId, routine.routineId, normalizeName(query.name))).map(row => ({
            position: row.position, type: row.setType, kg: row.weightKg, reps: row.repetitions, achievedAt: row.achievedAt,
          }))
        : await tx
        .select({
          position: exerciseRecords.position,
          type: exerciseRecords.setType,
          kg: exerciseRecords.weightKg,
          reps: exerciseRecords.repetitions,
          achievedAt: exerciseRecords.achievedAt,
        })
        .from(exerciseRecords)
        .innerJoin(exercises, eq(exerciseRecords.exerciseId, exercises.id))
        .where(
          and(
            eq(exercises.userId, userId),
            eq(exercises.normalizedName, normalizeName(query.name)),
          ),
        )
        .orderBy(asc(exerciseRecords.position));

      if (records.length === 0) {
        set.status = 404;
        return { message: 'Aún no hay un récord para este ejercicio' };
      }

      return {
        completedAt: records[0].achievedAt,
        sets: records.map((record) => ({
          position: record.position,
          type: record.type,
          kg: Number(record.kg),
          reps: record.reps,
        })),
      };
    }, { isolationLevel: 'repeatable read', accessMode: 'read only' });
  },
  {
    query: t.Object({
      name: t.String({ minLength: 1, maxLength: 160 }),
      routineId: t.Optional(t.String({ format: 'uuid' })),
    }),
  },
);

return app;
}

if (import.meta.main) {
const client = postgres(databaseUrl, { max: 10 });
await migrateAuth(client);
const app = createApp(drizzle(client), {
  clientId: process.env.GOOGLE_CLIENT_ID ?? '',
  clientSecret: process.env.GOOGLE_CLIENT_SECRET ?? '',
  redirectUri: process.env.GOOGLE_REDIRECT_URI ?? '',
  legacyOwnerEmail: process.env.LEGACY_OWNER_EMAIL,
  webOrigin: process.env.WEB_ORIGIN,
  skipLogin: process.env.SKIP_LOGIN === 'true',
});
const shutdown = async () => {
  app.stop();
  await client.end();
};
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

app.listen({ hostname: '0.0.0.0', port });

console.log(`API Elysia disponible en http://0.0.0.0:${port}`);

}
