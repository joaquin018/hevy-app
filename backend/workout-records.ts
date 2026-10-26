import { and, asc, eq, inArray, sql } from 'drizzle-orm';
import type { Database } from './auth.ts';
import { exerciseRecords, workoutSessionExercises, workoutSessions, workoutSets } from './schema.ts';

type Tx = Parameters<Parameters<Database['transaction']>[0]>[0];

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
    .where(and(eq(workoutSessions.userId, userId), inArray(workoutSessionExercises.exerciseId, exerciseIds), eq(workoutSets.completed, true)))
    .orderBy(asc(workoutSessions.createdAt), asc(workoutSessions.id), asc(workoutSessionExercises.position), asc(workoutSets.position));

  const references = new Map<string, typeof rows[number]>();
  for (const row of rows) {
    const key = `${row.exerciseId}:${row.position}`;
    const previous = references.get(key);
    // Match the save/history policy: either a higher weight or more reps
    // replaces the entire reference, including its set type and timestamp.
    if (!previous || Number(row.weightKg) > Number(previous.weightKg) || row.repetitions > previous.repetitions) {
      references.set(key, row);
    }
  }
  await tx.delete(exerciseRecords).where(inArray(exerciseRecords.exerciseId, exerciseIds));
  if (references.size) await tx.insert(exerciseRecords).values([...references.values()]);
}
