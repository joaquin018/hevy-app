import type { TransactionSql } from 'postgres';

export async function migrateExerciseCatalog(tx: TransactionSql) {
  await tx`CREATE TABLE IF NOT EXISTS exercise_catalog (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL CHECK (length(btrim(name)) > 0),
    normalized_name TEXT NOT NULL CHECK (length(normalized_name) > 0),
    muscle_group TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  )`;
  await tx`CREATE UNIQUE INDEX IF NOT EXISTS exercise_catalog_normalized_name_idx ON exercise_catalog(normalized_name)`;
  // Preserve every private row/ID. Prefer an existing classification, then the
  // earliest description, without letting later restarts replace public names.
  await tx`INSERT INTO exercise_catalog(name, normalized_name, muscle_group, created_at)
    SELECT DISTINCT ON (normalized_name) btrim(name), normalized_name, nullif(btrim(muscle_group), ''), created_at
    FROM exercises WHERE length(btrim(name)) > 0 AND length(normalized_name) > 0
    ORDER BY normalized_name, (nullif(btrim(muscle_group), '') IS NOT NULL) DESC, created_at, id
    ON CONFLICT (normalized_name) DO UPDATE SET muscle_group = excluded.muscle_group
    WHERE exercise_catalog.muscle_group IS NULL AND excluded.muscle_group IS NOT NULL`;
}
