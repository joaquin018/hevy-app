import type { TransactionSql } from 'postgres';

// Called inside the same migration transaction/advisory lock as the base schema.
export async function migrateRoutines(tx: TransactionSql) {
  await tx`ALTER TABLE users ADD COLUMN IF NOT EXISTS routine_version INTEGER NOT NULL DEFAULT 0`;
  await tx`CREATE INDEX IF NOT EXISTS users_email_prefix_idx
    ON users ((lower(email) COLLATE "C")) WHERE google_subject IS NOT NULL AND email IS NOT NULL`;
  await tx`CREATE INDEX IF NOT EXISTS routine_folders_user_position_idx ON routine_folders(user_id, position, id)`;
  await tx`CREATE INDEX IF NOT EXISTS routines_folder_position_idx ON routines(folder_id, position, id)`;
  await tx`CREATE INDEX IF NOT EXISTS routine_exercises_routine_position_idx ON routine_exercises(routine_id, position)`;
  await tx`CREATE TABLE IF NOT EXISTS routine_shares (
    id UUID PRIMARY KEY,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source_routine_id UUID REFERENCES routines(id) ON DELETE SET NULL,
    imported_routine_id UUID REFERENCES routines(id) ON DELETE SET NULL,
    snapshot JSONB NOT NULL CHECK (octet_length(snapshot::text) <= 65536),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected', 'revoked')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT date_trunc('milliseconds', now()),
    resolved_at TIMESTAMPTZ,
    CHECK (sender_id <> recipient_id)
  )`;
  // One composite index serves pending inbox, badge and recipient FK cleanup.
  await tx`CREATE INDEX IF NOT EXISTS routine_shares_recipient_idx
    ON routine_shares(recipient_id, status, created_at DESC, id DESC)`;
  await tx`CREATE INDEX IF NOT EXISTS routine_shares_sender_idx ON routine_shares(sender_id, created_at DESC, id DESC)`;
  await tx`CREATE UNIQUE INDEX IF NOT EXISTS routine_shares_pending_unique_idx
    ON routine_shares(sender_id, recipient_id, source_routine_id) WHERE status = 'pending'`;
  // Keep FK deletions bounded, including shares already resolved.
  await tx`CREATE INDEX IF NOT EXISTS routine_shares_source_idx ON routine_shares(source_routine_id) WHERE source_routine_id IS NOT NULL`;
  await tx`CREATE INDEX IF NOT EXISTS routine_shares_imported_idx ON routine_shares(imported_routine_id) WHERE imported_routine_id IS NOT NULL`;
}
