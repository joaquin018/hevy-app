import { and, desc, eq, sql } from 'drizzle-orm';
import type { Database } from './auth.ts';
import { RoutineError } from './routine-library.ts';
import { activeWorkoutDrafts, routineFolders, routines, workoutSessions } from './schema.ts';

type Tx = Parameters<Parameters<Database['transaction']>[0]>[0];
type Context = { routineId: string | null; isolateResults: boolean };

export async function resolveRoutineContext(tx: Tx, userId: string, input: { routineId?: string; routineName?: string }): Promise<Context> {
  if (input.routineId) {
    const [routine] = await tx.select({ isolateResults: routines.isolateResults }).from(routines)
      .innerJoin(routineFolders, eq(routineFolders.id, routines.folderId))
      .where(and(eq(routines.id, input.routineId), eq(routineFolders.userId, userId)));
    if (routine) return { routineId: input.routineId, isolateResults: routine.isolateResults };
    // A deleted routine can still own an unfinished workout or past sessions.
    // Its retained identity must not turn isolated results into shared ones.
    const [draft] = await tx.select({ isolateResults: activeWorkoutDrafts.isolateResults }).from(activeWorkoutDrafts)
      .where(and(eq(activeWorkoutDrafts.userId, userId), eq(activeWorkoutDrafts.routineId, input.routineId)));
    if (draft) return { routineId: input.routineId, isolateResults: draft.isolateResults };
    const [session] = await tx.select({ isolateResults: workoutSessions.isolateResults }).from(workoutSessions)
      .where(and(eq(workoutSessions.userId, userId), eq(workoutSessions.routineId, input.routineId)))
      .orderBy(desc(workoutSessions.createdAt), desc(workoutSessions.id)).limit(1);
    if (session) return { routineId: input.routineId, isolateResults: session.isolateResults };
    throw new RoutineError(404, 'ROUTINE_NOT_FOUND', 'No se encontró la rutina de este entrenamiento.');
  }
  if (input.routineName) {
    const matches = await tx.select({ id: routines.id, isolateResults: routines.isolateResults }).from(routines)
      .innerJoin(routineFolders, eq(routineFolders.id, routines.folderId))
      .where(and(eq(routineFolders.userId, userId), sql`lower(btrim(${routines.name})) = ${input.routineName.trim().toLocaleLowerCase('es')}`));
    if (matches.some(r => r.isolateResults)) {
      throw new RoutineError(428, 'ROUTINE_UPGRADE_REQUIRED', 'Recarga la app para entrenar con resultados aislados.');
    }
    if (matches.length === 1) return { routineId: matches[0].id, isolateResults: false };
  }
  return { routineId: null, isolateResults: false };
}
