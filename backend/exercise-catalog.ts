import { sql } from 'drizzle-orm';
import type { Database } from './auth.ts';
import { exerciseCatalog } from './schema.ts';

type Tx = Parameters<Parameters<Database['transaction']>[0]>[0];
type Description = { name: string; muscleGroup?: string | null };

// Only descriptions are shared. Per-user exercise IDs continue to own records
// and rest preferences, so using a catalog entry never imports another history.
export async function publishExercises(tx: Tx, entries: Description[]) {
  const distinct = new Map<string, { name: string; normalizedName: string; muscleGroup: string | null }>();
  for (const entry of entries) {
    const name = entry.name.trim(), normalizedName = name.toLocaleLowerCase('es');
    if (!name) continue;
    const muscleGroup = entry.muscleGroup?.trim() || null;
    const current = distinct.get(normalizedName);
    if (!current) distinct.set(normalizedName, { name, normalizedName, muscleGroup });
    else if (current.muscleGroup === null) current.muscleGroup = muscleGroup;
  }
  // Consistent lock order also covers concurrent imports/workouts with the
  // same new exercises listed in a different order.
  const values = [...distinct.values()].sort((a, b) => a.normalizedName < b.normalizedName ? -1 : a.normalizedName > b.normalizedName ? 1 : 0);
  if (!values.length) return;
  await tx.insert(exerciseCatalog).values(values).onConflictDoUpdate({
    target: exerciseCatalog.normalizedName,
    set: { muscleGroup: sql`coalesce(${exerciseCatalog.muscleGroup}, excluded.muscle_group)` },
    setWhere: sql`${exerciseCatalog.muscleGroup} IS NULL AND excluded.muscle_group IS NOT NULL`,
  });
}
