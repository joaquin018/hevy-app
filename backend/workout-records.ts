import { and, asc, eq, inArray, sql } from 'drizzle-orm';
import type { Database } from './auth.ts';
import { exerciseRecords, exercises, workoutSessionExercises, workoutSessions, workoutSets } from './schema.ts';

type Tx = Parameters<Parameters<Database['transaction']>[0]>[0];

type Reference = { exerciseId: string; position: number; setType: string; weightKg: string; repetitions: number; achievedAt: Date };
function referencesFrom(rows: Reference[]) {
  const references = new Map<string, Reference>();
  for (const row of rows) {
    const key = `${row.exerciseId}:${row.position}`;
    const previous = references.get(key);
    // Keep the existing policy: either higher weight or more reps replaces
    // the entire reference, including its set type and date.
    if (!previous || Number(row.weightKg) > Number(previous.weightKg) || row.repetitions > previous.repetitions) references.set(key, row);
  }
  return [...references.values()];
}

export async function readRoutineReferences(tx: Tx, userId: string, routineId: string, normalizedName: string) {
  const rows = await tx.select({
    exerciseId: exercises.id, position: workoutSets.position, setType: workoutSets.setType,
    weightKg: workoutSets.weightKg, repetitions: workoutSets.repetitions, achievedAt: workoutSessions.completedAt,
  }).from(exercises)
    .innerJoin(workoutSessionExercises, eq(workoutSessionExercises.exerciseId, exercises.id))
    .innerJoin(workoutSessions, eq(workoutSessions.id, workoutSessionExercises.sessionId))
    .innerJoin(workoutSets, eq(workoutSets.sessionExerciseId, workoutSessionExercises.id))
    .where(and(eq(exercises.userId, userId), eq(exercises.normalizedName, normalizedName), eq(workoutSessions.userId, userId),
      eq(workoutSessions.routineId, routineId), eq(workoutSessions.isolateResults, true), eq(workoutSets.completed, true)))
    .orderBy(asc(workoutSessions.createdAt), asc(workoutSessions.id), asc(workoutSessionExercises.position), asc(workoutSets.position));
  return referencesFrom(rows).sort((a, b) => a.position - b.position);
}

// Saving and deleting must share a lock: a record rebuild cannot race with a
// new session, and retrying a save must still find the original session.
export async function lockWorkoutWrites(tx: Tx, userId: string) {
  await tx.execute(sql`select pg_advisory_xact_lock(7132049, hashtext(${userId}))`);
}

export async function rebuildExerciseRecords(tx: Tx, userId: string, exerciseIds: string[]) {
  if (!exerciseIds.length) return;
  const rows = await tx.select({
    exerciseId: workoutSessionExercises.exerciseId,
    position: workoutSets.position,
    setType: workoutSets.setType,
    weightKg: workoutSets.weightKg,
    repetitions: workoutSets.repetitions,
    achievedAt: workoutSessions.completedAt,
  }).from(workoutSessions)
    .innerJoin(workoutSessionExercises, eq(workoutSessionExercises.sessionId, workoutSessions.id))
    .innerJoin(workoutSets, eq(workoutSets.sessionExerciseId, workoutSessionExercises.id))
    .where(and(eq(workoutSessions.userId, userId), eq(workoutSessions.isolateResults, false), inArray(workoutSessionExercises.exerciseId, exerciseIds), eq(workoutSets.completed, true)))
    .orderBy(asc(workoutSessions.createdAt), asc(workoutSessions.id), asc(workoutSessionExercises.position), asc(workoutSets.position));

  const references = referencesFrom(rows);
  await tx.delete(exerciseRecords).where(inArray(exerciseRecords.exerciseId, exerciseIds));
  if (references.length) await tx.insert(exerciseRecords).values(references);
}
