import type { Sql } from 'postgres';

export async function migrateAuth(client: Sql) {
  const schema = await Bun.file(new URL('./init.sql', import.meta.url)).text();
  await client.begin(async (tx) => {
    await tx`SELECT pg_advisory_xact_lock(7132048)`;
    await tx.unsafe(schema);
    await tx`ALTER TABLE users ADD COLUMN IF NOT EXISTS email TEXT`;
    await tx`ALTER TABLE users ADD COLUMN IF NOT EXISTS google_subject TEXT`;
    await tx`CREATE UNIQUE INDEX IF NOT EXISTS users_google_subject_idx ON users(google_subject)`;
    await tx`CREATE TABLE IF NOT EXISTS auth_sessions (
      token_hash TEXT PRIMARY KEY, user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      expires_at TIMESTAMPTZ NOT NULL
    )`;
    await tx`CREATE INDEX IF NOT EXISTS auth_sessions_expiry_idx ON auth_sessions(expires_at)`;
    await tx`CREATE TABLE IF NOT EXISTS login_attempts (
      token_hash TEXT PRIMARY KEY, state TEXT NOT NULL UNIQUE, nonce TEXT NOT NULL,
      verifier TEXT NOT NULL, user_id UUID REFERENCES users(id) ON DELETE CASCADE,
      status TEXT NOT NULL DEFAULT 'pending', expires_at TIMESTAMPTZ NOT NULL
    )`;
    await tx`CREATE INDEX IF NOT EXISTS login_attempts_expiry_idx ON login_attempts(expires_at)`;
    await tx`ALTER TABLE login_attempts ADD COLUMN IF NOT EXISTS browser_flow BOOLEAN NOT NULL DEFAULT FALSE`;
  });
}
