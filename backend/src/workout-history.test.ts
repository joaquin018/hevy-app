import { expect, test } from 'bun:test';
import { buildWorkoutHistory, type HistoryRow } from './workout-history.ts';

test('history retains past records, counts only improvements and sums volume', () => {
  const sessions = [1, 2, 3, 4].map((n) => ({
    id: String(n), routineName: 'Piernas', startedAt: new Date(`2026-09-0${n}`),
    completedAt: new Date(`2026-09-0${n}`), durationSeconds: 600,
  }));
  const rows: HistoryRow[] = [
    { sessionId: '1', kg: '40', reps: 8 },
    { sessionId: '2', kg: '45', reps: 8 },
    { sessionId: '3', kg: '40', reps: 6 },
    { sessionId: '4', kg: '50', reps: 8 },
  ].map((row) => ({ ...row, sessionExerciseId: row.sessionId, exerciseId: 'squat', name: 'Sentadilla', position: 0, type: 'normal' }));
  const history = buildWorkoutHistory(sessions, rows);
  expect(history.map((s) => s.id)).toEqual(['4', '3', '2', '1']);
  expect(history.map((s) => s.records)).toEqual([1, 0, 1, 0]);
  expect(history.map((s) => s.volumeKg)).toEqual([400, 240, 360, 320]);
  expect(buildWorkoutHistory(sessions.slice(0, 2), rows.slice(0, 2))[0]?.records).toBe(history[2]?.records);
});

test('references are separate for each exercise and set position; repetitions can improve', () => {
  const sessions = ['a', 'b', 'empty'].map((id) => ({ id, routineName: null, startedAt: new Date(), completedAt: new Date(), durationSeconds: 10 }));
  const row = { sessionId: 'a', sessionExerciseId: 'a', exerciseId: 'press', name: 'Press', position: 0, type: 'normal', kg: '10.5', reps: 10 };
  const history = buildWorkoutHistory(sessions, [row,
    { ...row, sessionId: 'b', sessionExerciseId: 'b', reps: 12 },
    { ...row, sessionId: 'b', sessionExerciseId: 'b', position: 1 },
    { ...row, sessionId: 'b', sessionExerciseId: 'other', exerciseId: 'other' },
  ]);
  const b = history.find((s) => s.id === 'b')!;
  expect(b.records).toBe(1);
  expect(b.exercises).toHaveLength(2);
  expect(b.exercises[0]?.sets).toHaveLength(2);
  expect(b.volumeKg).toBe(336);
  expect(history.find((s) => s.id === 'empty')?.exercises).toEqual([]);
});
