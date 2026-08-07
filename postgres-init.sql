CREATE TABLE IF NOT EXISTS greetings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO greetings (message)
SELECT 'Hola desde Elysia + PostgreSQL'
WHERE NOT EXISTS (SELECT 1 FROM greetings);
