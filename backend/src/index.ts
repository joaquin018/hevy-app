import { Elysia, t } from 'elysia';
import { and, asc, desc, eq } from 'drizzle-orm';
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';

import {
  activeWorkoutDrafts,
  exercises,
  exerciseRecords,
  routineExercises,
  routineFolders,
  routines,
  users,
  workoutSessionExercises,
  workoutSessions,
  workoutSets,
} from './schema.ts';

const port = Number(process.env.PORT ?? 3000);
const databaseUrl = process.env.DATABASE_URL ??
  'postgres://hevy:hevy_dev_password@localhost:5432/hevy';
const developmentUserId = process.env.DEVELOPMENT_USER_ID ??
  '00000000-0000-4000-8000-000000000001';
const client = postgres(databaseUrl, { max: 10 });
const db = drizzle(client);
const app = new Elysia();

const normalizeName = (name: string) => name.trim().toLocaleLowerCase('es');

app.get('/health', () => ({ status: 'ok' }));

app.get('/workout-draft', async ({ set }) => {
  const [draft] = await db
    .select()
    .from(activeWorkoutDrafts)
    .where(eq(activeWorkoutDrafts.userId, developmentUserId))
    .limit(1);
  if (!draft) {
    set.status = 404;
    return { message: 'No hay un entrenamiento en curso' };
  }
  return draft;
});

app.put(
  '/workout-draft',
  async ({ body }) => {
    await db.transaction(async (tx) => {
      await tx
        .insert(users)
        .values({ id: developmentUserId, displayName: 'Usuario de desarrollo' })
        .onConflictDoNothing({ target: users.id });
      await tx
        .insert(activeWorkoutDrafts)
        .values({
          userId: developmentUserId,
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

app.delete('/workout-draft', async () => {
  await db
    .delete(activeWorkoutDrafts)
    .where(eq(activeWorkoutDrafts.userId, developmentUserId));
  return { deleted: true };
});

app.get('/exercises', async () => {
  return db
    .select({ name: exercises.name, muscleGroup: exercises.muscleGroup })
    .from(exercises)
    .where(eq(exercises.userId, developmentUserId))
    .orderBy(desc(exercises.createdAt));
});

app.post(
  '/exercises',
  async ({ body, set }) => {
    const [exercise] = await db.transaction(async (tx) => {
      await tx
        .insert(users)
        .values({ id: developmentUserId, displayName: 'Usuario de desarrollo' })
        .onConflictDoNothing({ target: users.id });
      return tx
        .insert(exercises)
        .values({
          userId: developmentUserId,
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
  async ({ query }) => {
    const [exercise] = await db
      .select({ restSeconds: exercises.restSeconds })
      .from(exercises)
      .where(
        and(
          eq(exercises.userId, developmentUserId),
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
  async ({ body }) => {
    const [exercise] = await db.transaction(async (tx) => {
      await tx
        .insert(users)
        .values({ id: developmentUserId, displayName: 'Usuario de desarrollo' })
        .onConflictDoNothing({ target: users.id });
      return tx
        .insert(exercises)
        .values({
          userId: developmentUserId,
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

app.get('/routine-folders', async () => {
  const savedFolders = await db
    .select()
    .from(routineFolders)
    .where(eq(routineFolders.userId, developmentUserId))
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
  async ({ body }) => {
    await db.transaction(async (tx) => {
      await tx
        .insert(users)
        .values({ id: developmentUserId, displayName: 'Usuario de desarrollo' })
        .onConflictDoNothing({ target: users.id });
      await tx
        .delete(routineFolders)
        .where(eq(routineFolders.userId, developmentUserId));

      for (const [folderPosition, inputFolder] of body.folders.entries()) {
        const [folder] = await tx
          .insert(routineFolders)
          .values({
            userId: developmentUserId,
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
  async ({ body, set }) => {
    const created = await db.transaction(async (tx) => {
      await tx
        .insert(users)
        .values({ id: developmentUserId, displayName: 'Usuario de desarrollo' })
        .onConflictDoNothing({ target: users.id });

      const [session] = await tx
        .insert(workoutSessions)
        .values({
          userId: developmentUserId,
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
            userId: developmentUserId,
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
  async ({ query, set }) => {
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
          eq(exercises.userId, developmentUserId),
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

const shutdown = async () => {
  app.stop();
  await client.end();
};
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

app.listen({ hostname: '0.0.0.0', port });

console.log(`API Elysia disponible en http://0.0.0.0:${port}`);
