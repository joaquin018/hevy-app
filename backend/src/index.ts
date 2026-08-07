import { Elysia, t } from 'elysia';
import { desc } from 'drizzle-orm';
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';

import { greetings } from './schema.ts';

const port = Number(process.env.PORT ?? 3000);
const databaseUrl = process.env.DATABASE_URL ??
  'postgres://hevy:hevy_dev_password@localhost:5432/hevy';
const client = postgres(databaseUrl, { max: 10 });
const db = drizzle(client);
const app = new Elysia();

app.get('/health', () => ({ status: 'ok' }));

app.get('/hello', async () => {
  const [saved] = await db
    .select()
    .from(greetings)
    .orderBy(desc(greetings.updatedAt))
    .limit(1);

  return saved ?? { message: 'Hola desde Elysia + PostgreSQL' };
});

app.post('/hello', async ({ body, set }) => {
  const [created] = await db
    .insert(greetings)
    .values({ message: body.message })
    .returning();
  set.status = 201;
  return created;
}, {
  body: t.Object({
    message: t.String({ minLength: 1, maxLength: 200 }),
  }),
});

const shutdown = async () => {
  app.stop();
  await client.end();
};
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

app.listen({ hostname: '0.0.0.0', port });

console.log(`API Elysia disponible en http://0.0.0.0:${port}`);
