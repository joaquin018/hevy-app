import { sql } from 'drizzle-orm';
import {
  boolean,
  integer,
  index,
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
  routineVersion: integer('routine_version').notNull().default(0),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
}, (table) => [index('users_email_prefix_idx').on(sql`lower(${table.email}) COLLATE "C"`)
  .where(sql`${table.googleSubject} IS NOT NULL AND ${table.email} IS NOT NULL`)]);

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
  browserFlow: boolean('browser_flow').notNull().default(false),
  userId: uuid('user_id').references(() => users.id, { onDelete: 'cascade' }),
  status: text('status').notNull().default('pending'),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
});

export const exerciseCatalog = pgTable('exercise_catalog', {
  id: uuid('id').primaryKey().defaultRandom(),
  name: text('name').notNull(),
  normalizedName: text('normalized_name').notNull(),
  muscleGroup: text('muscle_group'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
}, table => [uniqueIndex('exercise_catalog_normalized_name_idx').on(table.normalizedName)]);

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
}, (table) => [index('routine_folders_user_position_idx').on(table.userId, table.position, table.id)]);

export const routines = pgTable('routines', {
  id: uuid('id').primaryKey().defaultRandom(),
  folderId: uuid('folder_id')
    .notNull()
    .references(() => routineFolders.id, { onDelete: 'cascade' }),
  name: text('name').notNull(),
  position: integer('position').notNull(),
}, (table) => [index('routines_folder_position_idx').on(table.folderId, table.position, table.id)]);

export const routineExercises = pgTable('routine_exercises', {
  id: uuid('id').primaryKey().defaultRandom(),
  routineId: uuid('routine_id')
    .notNull()
    .references(() => routines.id, { onDelete: 'cascade' }),
  name: text('name').notNull(),
  position: integer('position').notNull(),
}, (table) => [index('routine_exercises_routine_position_idx').on(table.routineId, table.position)]);

export type RoutineSnapshot = {
  version: 1;
  name: string;
  exercises: { name: string; muscleGroup: string | null; restSeconds: number }[];
};

export type FolderSnapshot = {
  version: 2;
  name: string;
  routines: Omit<RoutineSnapshot, 'version'>[];
};

export const routineShares = pgTable('routine_shares', {
  id: uuid('id').primaryKey(),
  senderId: uuid('sender_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  recipientId: uuid('recipient_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
  sourceRoutineId: uuid('source_routine_id').references(() => routines.id, { onDelete: 'set null' }),
  importedRoutineId: uuid('imported_routine_id').references(() => routines.id, { onDelete: 'set null' }),
  sourceFolderId: uuid('source_folder_id').references(() => routineFolders.id, { onDelete: 'set null' }),
  importedFolderId: uuid('imported_folder_id').references(() => routineFolders.id, { onDelete: 'set null' }),
  snapshot: jsonb('snapshot').$type<RoutineSnapshot | FolderSnapshot>().notNull(),
  status: text('status').notNull().default('pending'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  resolvedAt: timestamp('resolved_at', { withTimezone: true }),
}, (table) => [
  index('routine_shares_sender_idx').on(table.senderId, table.createdAt.desc(), table.id.desc()),
  index('routine_shares_recipient_idx').on(table.recipientId, table.status, table.createdAt.desc(), table.id.desc()),
  uniqueIndex('routine_shares_pending_unique_idx').on(table.senderId, table.recipientId, table.sourceRoutineId).where(sql`${table.status} = 'pending'`),
  index('routine_shares_source_idx').on(table.sourceRoutineId).where(sql`${table.sourceRoutineId} IS NOT NULL`),
  index('routine_shares_imported_idx').on(table.importedRoutineId).where(sql`${table.importedRoutineId} IS NOT NULL`),
  uniqueIndex('routine_shares_pending_folder_unique_idx').on(table.senderId, table.recipientId, table.sourceFolderId).where(sql`${table.status} = 'pending'`),
  index('routine_shares_source_folder_idx').on(table.sourceFolderId).where(sql`${table.sourceFolderId} IS NOT NULL`),
  index('routine_shares_imported_folder_idx').on(table.importedFolderId).where(sql`${table.importedFolderId} IS NOT NULL`),
]);

export const activeWorkoutDrafts = pgTable('active_workout_drafts', {
  userId: uuid('user_id').primaryKey().references(() => users.id, { onDelete: 'cascade' }),
  routineName: text('routine_name').notNull(),
  startedAt: timestamp('started_at', { withTimezone: true }).notNull(),
  originalExercises: jsonb('original_exercises').notNull(),
  exercises: jsonb('exercises').notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
});
