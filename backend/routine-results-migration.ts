import type { TransactionSql } from 'postgres';

export async function migrateRoutineResults(tx: TransactionSql) {
  const [previous] = await tx`SELECT EXISTS (
    SELECT 1 FROM information_schema.columns WHERE table_schema = current_schema()
      AND table_name = 'workout_sessions' AND column_name = 'routine_id'
  ) AS installed`;
  await tx`ALTER TABLE routines ADD COLUMN IF NOT EXISTS isolate_results BOOLEAN NOT NULL DEFAULT FALSE`;
  await tx`ALTER TABLE workout_sessions ADD COLUMN IF NOT EXISTS routine_id UUID`;
  await tx`ALTER TABLE workout_sessions ADD COLUMN IF NOT EXISTS isolate_results BOOLEAN NOT NULL DEFAULT FALSE`;
  await tx`ALTER TABLE active_workout_drafts ADD COLUMN IF NOT EXISTS routine_id UUID`;
  await tx`ALTER TABLE active_workout_drafts ADD COLUMN IF NOT EXISTS isolate_results BOOLEAN NOT NULL DEFAULT FALSE`;
  // Legacy sessions only have names. Associate unambiguous names once, never
  // on later restarts where a newly created routine could reuse an old name.
  if (!previous.installed) {
    await tx`WITH candidates AS (
      SELECT f.user_id, lower(btrim(r.name)) AS name, (array_agg(r.id))[1] AS id
      FROM routines r JOIN routine_folders f ON f.id = r.folder_id
      GROUP BY f.user_id, lower(btrim(r.name)) HAVING count(*) = 1
    ) UPDATE workout_sessions s SET routine_id = c.id FROM candidates c
      WHERE s.user_id = c.user_id AND lower(btrim(s.routine_name)) = c.name`;
    await tx`WITH candidates AS (
      SELECT f.user_id, lower(btrim(r.name)) AS name, (array_agg(r.id))[1] AS id
      FROM routines r JOIN routine_folders f ON f.id = r.folder_id
      GROUP BY f.user_id, lower(btrim(r.name)) HAVING count(*) = 1
    ) UPDATE active_workout_drafts d SET routine_id = c.id FROM candidates c
      WHERE d.user_id = c.user_id AND lower(btrim(d.routine_name)) = c.name`;
  }
  await tx`CREATE INDEX IF NOT EXISTS workout_sessions_user_routine_idx ON workout_sessions(user_id, routine_id, created_at, id)`;
  await tx`CREATE INDEX IF NOT EXISTS workout_session_exercises_exercise_idx ON workout_session_exercises(exercise_id, session_id)`;
  await tx`CREATE INDEX IF NOT EXISTS workout_sets_session_position_idx ON workout_sets(session_exercise_id, position)`;
}
