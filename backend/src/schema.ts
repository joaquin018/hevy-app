import { pgTable, text, timestamp, uuid } from 'drizzle-orm/pg-core';

export const greetings = pgTable('greetings', {
  id: uuid('id').primaryKey().defaultRandom(),
  message: text('message').notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true })
    .notNull()
    .defaultNow(),
});
