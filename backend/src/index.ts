import { Elysia, t } from 'elysia';
import { and, asc, desc, eq } from 'drizzle-orm';
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';

import {
  exercises,
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

        if (inputExercise.sets.length > 0) {
          await tx.insert(workoutSets).values(
            inputExercise.sets.map((workoutSet, position) => ({
              sessionExerciseId: sessionExercise.id,
              position,
              setType: workoutSet.type,
              weightKg: String(workoutSet.kg),
              repetitions: workoutSet.reps,
              completed: workoutSet.completed,
            })),
          );
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
    const [previousExercise] = await db
      .select({
        sessionExerciseId: workoutSessionExercises.id,
        sessionId: workoutSessions.id,
        completedAt: workoutSessions.completedAt,
      })
      .from(workoutSessionExercises)
      .innerJoin(
        workoutSessions,
        eq(workoutSessionExercises.sessionId, workoutSessions.id),
      )
      .innerJoin(exercises, eq(workoutSessionExercises.exerciseId, exercises.id))
      .where(
        and(
          eq(workoutSessions.userId, developmentUserId),
          eq(exercises.normalizedName, normalizeName(query.name)),
        ),
      )
      .orderBy(desc(workoutSessions.completedAt))
      .limit(1);

    if (!previousExercise) {
      set.status = 404;
      return { message: 'Aún no hay una sesión anterior para este ejercicio' };
    }

    const sets = await db
      .select({
        position: workoutSets.position,
        type: workoutSets.setType,
        kg: workoutSets.weightKg,
        reps: workoutSets.repetitions,
      })
      .from(workoutSets)
      .where(
        and(
          eq(workoutSets.sessionExerciseId, previousExercise.sessionExerciseId),
          eq(workoutSets.completed, true),
        ),
      )
      .orderBy(asc(workoutSets.position));

    return {
      sessionId: previousExercise.sessionId,
      completedAt: previousExercise.completedAt,
      sets: sets.map((workoutSet) => ({
        ...workoutSet,
        kg: Number(workoutSet.kg),
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
