CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  display_name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS exercises (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  normalized_name TEXT NOT NULL,
  muscle_group TEXT,
  rest_seconds INTEGER NOT NULL DEFAULT 180,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE exercises
  ADD COLUMN IF NOT EXISTS rest_seconds INTEGER NOT NULL DEFAULT 180;
CREATE UNIQUE INDEX IF NOT EXISTS exercises_user_normalized_name_idx
  ON exercises(user_id, normalized_name);

CREATE TABLE IF NOT EXISTS workout_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  routine_name TEXT,
  started_at TIMESTAMPTZ NOT NULL,
  completed_at TIMESTAMPTZ NOT NULL,
  duration_seconds INTEGER NOT NULL CHECK (duration_seconds >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS workout_session_exercises (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES workout_sessions(id) ON DELETE CASCADE,
  exercise_id UUID NOT NULL REFERENCES exercises(id) ON DELETE RESTRICT,
  position INTEGER NOT NULL CHECK (position >= 0)
);

CREATE TABLE IF NOT EXISTS workout_sets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_exercise_id UUID NOT NULL REFERENCES workout_session_exercises(id) ON DELETE CASCADE,
  position INTEGER NOT NULL CHECK (position >= 0),
  set_type TEXT NOT NULL DEFAULT 'normal',
  weight_kg NUMERIC(8, 2) NOT NULL CHECK (weight_kg >= 0),
  repetitions INTEGER NOT NULL CHECK (repetitions >= 0),
  completed BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS exercise_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  exercise_id UUID NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
  position INTEGER NOT NULL CHECK (position >= 0),
  set_type TEXT NOT NULL DEFAULT 'normal',
  weight_kg NUMERIC(8, 2) NOT NULL CHECK (weight_kg >= 0),
  repetitions INTEGER NOT NULL CHECK (repetitions >= 0),
  achieved_at TIMESTAMPTZ NOT NULL,
  CONSTRAINT exercise_records_exercise_position_unique
    UNIQUE (exercise_id, position)
);

CREATE TABLE IF NOT EXISTS routine_folders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  position INTEGER NOT NULL CHECK (position >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS routines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  folder_id UUID NOT NULL REFERENCES routine_folders(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  position INTEGER NOT NULL CHECK (position >= 0)
);

CREATE TABLE IF NOT EXISTS routine_exercises (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  routine_id UUID NOT NULL REFERENCES routines(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  position INTEGER NOT NULL CHECK (position >= 0)
);

CREATE TABLE IF NOT EXISTS active_workout_drafts (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  routine_name TEXT NOT NULL,
  started_at TIMESTAMPTZ NOT NULL,
  original_exercises JSONB NOT NULL,
  exercises JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO users (id, display_name)
VALUES ('00000000-0000-4000-8000-000000000001', 'Usuario de desarrollo')
ON CONFLICT (id) DO NOTHING;
