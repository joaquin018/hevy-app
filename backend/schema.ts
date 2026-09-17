import {
  boolean,
  integer,
  jsonb,
  numeric,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from 'drizzle-orm/pg-core';

export const users = pgTable('users', {
  id: uuid('id').primaryKey().defaultRandom(),
  displayName: text('display_name').notNull(),
  email: text('email'),
  googleSubject: text('google_subject').unique(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
});

export const authSessions = pgTable('auth_sessions', {
  tokenHash: text('token_hash').primaryKey(),
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
});

export const loginAttempts = pgTable('login_attempts', {
  tokenHash: text('token_hash').primaryKey(),
  state: text('state').notNull().unique(),
  nonce: text('nonce').notNull(),
  verifier: text('verifier').notNull(),
  userId: uuid('user_id').references(() => users.id, { onDelete: 'cascade' }),
  status: text('status').notNull().default('pending'),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
});

export const exercises = pgTable(
  'exercises',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
    name: text('name').notNull(),
    normalizedName: text('normalized_name').notNull(),
    muscleGroup: text('muscle_group'),
    restSeconds: integer('rest_seconds').notNull().default(180),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    uniqueIndex('exercises_user_normalized_name_idx').on(
      table.userId,
      table.normalizedName,
    ),
  ],
);

export const workoutSessions = pgTable('workout_sessions', {
  id: uuid('id').primaryKey().defaultRandom(),
  userId: uuid('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  routineName: text('routine_name'),
  startedAt: timestamp('started_at', { withTimezone: true }).notNull(),
  completedAt: timestamp('completed_at', { withTimezone: true }).notNull(),
  durationSeconds: integer('duration_seconds').notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
});

export const workoutSessionExercises = pgTable('workout_session_exercises', {
  id: uuid('id').primaryKey().defaultRandom(),
  sessionId: uuid('session_id').notNull().references(() => workoutSessions.id, { onDelete: 'cascade' }),
  exerciseId: uuid('exercise_id').notNull().references(() => exercises.id, { onDelete: 'restrict' }),
  position: integer('position').notNull(),
});

export const workoutSets = pgTable('workout_sets', {
  id: uuid('id').primaryKey().defaultRandom(),
  sessionExerciseId: uuid('session_exercise_id').notNull().references(
    () => workoutSessionExercises.id,
    { onDelete: 'cascade' },
  ),
  position: integer('position').notNull(),
  setType: text('set_type').notNull().default('normal'),
  weightKg: numeric('weight_kg', { precision: 8, scale: 2 }).notNull(),
  repetitions: integer('repetitions').notNull(),
  completed: boolean('completed').notNull().default(true),
});

export const exerciseRecords = pgTable(
  'exercise_records',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    exerciseId: uuid('exercise_id')
      .notNull()
      .references(() => exercises.id, { onDelete: 'cascade' }),
    position: integer('position').notNull(),
    setType: text('set_type').notNull().default('normal'),
    weightKg: numeric('weight_kg', { precision: 8, scale: 2 }).notNull(),
    repetitions: integer('repetitions').notNull(),
    achievedAt: timestamp('achieved_at', { withTimezone: true }).notNull(),
  },
  (table) => [
    uniqueIndex('exercise_records_exercise_position_idx').on(
      table.exerciseId,
      table.position,
    ),
  ],
);

export const routineFolders = pgTable('routine_folders', {
  id: uuid('id').primaryKey().defaultRandom(),
  userId: uuid('user_id')
    .notNull()
    .references(() => users.id, { onDelete: 'cascade' }),
  name: text('name').notNull(),
  position: integer('position').notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
});

export const routines = pgTable('routines', {
  id: uuid('id').primaryKey().defaultRandom(),
  folderId: uuid('folder_id')
    .notNull()
    .references(() => routineFolders.id, { onDelete: 'cascade' }),
  name: text('name').notNull(),
  position: integer('position').notNull(),
});

export const routineExercises = pgTable('routine_exercises', {
  id: uuid('id').primaryKey().defaultRandom(),
  routineId: uuid('routine_id')
    .notNull()
    .references(() => routines.id, { onDelete: 'cascade' }),
  name: text('name').notNull(),
  position: integer('position').notNull(),
});

export const activeWorkoutDrafts = pgTable('active_workout_drafts', {
  userId: uuid('user_id').primaryKey().references(() => users.id, { onDelete: 'cascade' }),
  routineName: text('routine_name').notNull(),
  startedAt: timestamp('started_at', { withTimezone: true }).notNull(),
  originalExercises: jsonb('original_exercises').notNull(),
  exercises: jsonb('exercises').notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
});
