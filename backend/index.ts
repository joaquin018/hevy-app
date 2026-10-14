import { Elysia, t } from 'elysia';
import { and, asc, desc, eq, sql } from 'drizzle-orm';
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import { buildWorkoutHistory } from './workout-history.ts';
import { authenticate, authRoutes, requestAuthorization, rejectCrossOrigin, validateAuthConfig, type Database, type AuthConfig, type GoogleProvider } from './auth.ts';
import { migrateAuth } from './auth-migration.ts';

import {
  activeWorkoutDrafts,
  exercises,
  exerciseRecords,
  routineExercises,
  routineFolders,
  routines,
  workoutSessionExercises,
  workoutSessions,
  workoutSets,
} from './schema.ts';

const port = Number(process.env.PORT ?? 3000);
const databaseUrl = process.env.DATABASE_URL ??
  'postgres://hevy:hevy_dev_password@localhost:5432/hevy';
export function createApp(db: Database, config: AuthConfig, provider?: GoogleProvider) {
validateAuthConfig(config);
const app = new Elysia().onRequest(({ request, status, set }) => {
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

app.put(
  '/workout-draft',
  async ({ body, userId }) => {
    await db.transaction(async (tx) => {
      await tx
        .insert(activeWorkoutDrafts)
        .values({
          userId: userId,
          routineName: body.routineName,
          startedAt: new Date(body.startedAt),
          originalExercises: body.originalExercises,
          exercises: body.exercises,
          updatedAt: new Date(),
        })
        .onConflictDoUpdate({
          target: activeWorkoutDrafts.userId,
          set: {
            routineName: body.routineName,
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

app.get('/exercises', async ({ userId }) => {
  return db
    .select({ name: exercises.name, muscleGroup: exercises.muscleGroup })
    .from(exercises)
    .where(eq(exercises.userId, userId))
    .orderBy(desc(exercises.createdAt));
});

app.post(
  '/exercises',
  async ({ body, set, userId }) => {
    const [exercise] = await db.transaction(async (tx) => {
      return tx
        .insert(exercises)
        .values({
          userId: userId,
          name: body.name.trim(),
          normalizedName: normalizeName(body.name),
          muscleGroup: body.muscleGroup.trim(),
        })
        .onConflictDoUpdate({
          target: [exercises.userId, exercises.normalizedName],
          set: {
            name: body.name.trim(),
            muscleGroup: body.muscleGroup.trim(),
          },
        })
        .returning({ name: exercises.name, muscleGroup: exercises.muscleGroup });
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
    const [exercise] = await db.transaction(async (tx) => {
      return tx
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

app.get('/routine-folders', async ({ userId }) => {
  const savedFolders = await db
    .select()
    .from(routineFolders)
    .where(eq(routineFolders.userId, userId))
    .orderBy(asc(routineFolders.position));

  return Promise.all(
    savedFolders.map(async (folder) => {
      const savedRoutines = await db
        .select()
        .from(routines)
        .where(eq(routines.folderId, folder.id))
        .orderBy(asc(routines.position));
      return {
        name: folder.name,
        routines: await Promise.all(
          savedRoutines.map(async (routine) => ({
            name: routine.name,
            exercises: (
              await db
                .select({ name: routineExercises.name })
                .from(routineExercises)
                .where(eq(routineExercises.routineId, routine.id))
                .orderBy(asc(routineExercises.position))
            ).map((exercise) => exercise.name),
          })),
        ),
      };
    }),
  );
});

app.put(
  '/routine-folders',
  async ({ body, userId }) => {
    await db.transaction(async (tx) => {
      await tx
        .delete(routineFolders)
        .where(eq(routineFolders.userId, userId));

      for (const [folderPosition, inputFolder] of body.folders.entries()) {
        const [folder] = await tx
          .insert(routineFolders)
          .values({
            userId: userId,
            name: inputFolder.name.trim(),
            position: folderPosition,
          })
          .returning();
        for (const [routinePosition, inputRoutine] of inputFolder.routines.entries()) {
          const [routine] = await tx
            .insert(routines)
            .values({
              folderId: folder.id,
              name: inputRoutine.name.trim(),
              position: routinePosition,
            })
            .returning();
          if (inputRoutine.exercises.length > 0) {
            await tx.insert(routineExercises).values(
              inputRoutine.exercises.map((name, position) => ({
                routineId: routine.id,
                name: name.trim(),
                position,
              })),
            );
          }
        }
      }
    });
    return { saved: true };
  },
  {
    body: t.Object({
      folders: t.Array(
        t.Object({
          name: t.String({ minLength: 1, maxLength: 120 }),
          routines: t.Array(
            t.Object({
              name: t.String({ minLength: 1, maxLength: 120 }),
              exercises: t.Array(
                t.String({ minLength: 1, maxLength: 160 }),
              ),
            }),
          ),
        }),
      ),
    }),
  },
);

app.post(
  '/workout-sessions',
  async ({ body, set, userId }) => {
    const created = await db.transaction(async (tx) => {

      // Retrying after a lost HTTP response must not duplicate a workout.
      await tx.execute(sql`select pg_advisory_xact_lock(hashtext(${userId}), hashtext(${new Date(body.startedAt).toISOString()}))`);
      const [existing] = await tx.select().from(workoutSessions).where(and(
        eq(workoutSessions.userId, userId), eq(workoutSessions.startedAt, new Date(body.startedAt)),
      )).limit(1);
      if (existing) return existing;

      const [session] = await tx
        .insert(workoutSessions)
        .values({
          userId: userId,
          routineName: body.routineName,
          startedAt: new Date(body.startedAt),
          completedAt: new Date(body.completedAt),
          durationSeconds: body.durationSeconds,
        })
        .returning();

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

      return session;
    });

    set.status = 201;
    return created;
  },
  {
    body: t.Object({
      routineName: t.Optional(t.String({ maxLength: 120 })),
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
    const records = await db
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
  },
  {
    query: t.Object({
      name: t.String({ minLength: 1, maxLength: 160 }),
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
