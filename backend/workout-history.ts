export type HistorySession = {
  id: string;
  routineName: string | null;
  routineId?: string | null;
  isolateResults?: boolean;
  startedAt: Date;
  completedAt: Date;
  durationSeconds: number;
};

export type HistoryRow = {
  sessionId: string;
  sessionExerciseId: string;
  exerciseId: string;
  name: string;
  position: number;
  type: string;
  kg: string;
  reps: number;
};

// Sessions and rows arrive in save order, matching the record update policy.
// Replaying it preserves past achievements even after a later personal best.
export function buildWorkoutHistory(sessions: HistorySession[], rows: HistoryRow[]) {
  const references = new Map<string, { kg: number; reps: number }>();
  const grouped = new Map<string, HistoryRow[]>();
  for (const row of rows) {
    const list = grouped.get(row.sessionId) ?? [];
    list.push(row);
    grouped.set(row.sessionId, list);
  }
  return sessions.map((session) => {
    const exercises = new Map<string, {
      id: string;
      name: string;
      sets: { position: number; type: string; kg: number; reps: number; isRecord: boolean }[];
    }>();
    let volumeKg = 0;
    let records = 0;
    for (const row of grouped.get(session.id) ?? []) {
      const kg = Number(row.kg);
      const scope = session.isolateResults ? session.routineId : 'shared';
      const key = `${scope}:${row.exerciseId}:${row.position}`;
      const previous = references.get(key);
      const improves = !previous || kg > previous.kg || row.reps > previous.reps;
      const isRecord = previous !== undefined && improves;
      if (improves) references.set(key, { kg, reps: row.reps });
      if (isRecord) records++;
      volumeKg += kg * row.reps;
      const exercise = exercises.get(row.sessionExerciseId) ?? {
        id: row.sessionExerciseId, name: row.name, sets: [],
      };
      exercise.sets.push({ position: row.position, type: row.type, kg, reps: row.reps, isRecord });
      exercises.set(row.sessionExerciseId, exercise);
    }
    return { ...session, volumeKg: Math.round(volumeKg * 100) / 100, records, exercises: [...exercises.values()] };
  }).sort((a, b) => b.startedAt.getTime() - a.startedAt.getTime() || b.id.localeCompare(a.id));
}
