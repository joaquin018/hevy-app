import { and, asc, desc, eq, inArray, sql } from 'drizzle-orm';
import { alias } from 'drizzle-orm/pg-core';
import type { Database } from './auth.ts';
import { exercises, routineExercises, routineFolders, routines, routineShares, users } from './schema.ts';

export class RoutineError extends Error {
  constructor(public status: number, public code: string, message: string) { super(message); }
}
const fail = (status: number, code: string, message: string): never => { throw new RoutineError(status, code, message); };
const normalize = (name: string) => name.trim().toLocaleLowerCase('es');
type Tx = Parameters<Parameters<Database['transaction']>[0]>[0];
export type LibraryPatch = {
  version: number;
  folders: { id: string; name: string; position: number }[];
  deletedFolders: string[];
  routines: { id: string; folderId: string; name: string; position: number; exercises?: string[] }[];
  deletedRoutines: string[];
};

async function lockLibrary(tx: Tx, userId: string) {
  // NO KEY UPDATE serializes a user's edits while allowing foreign-key checks
  // from other users sending routines to this account.
  const [owner] = await tx.select({ version: users.routineVersion }).from(users)
    .where(eq(users.id, userId)).for('no key update');
  if (!owner) fail(401, 'UNAUTHORIZED', 'Inicia sesión para continuar.');
  return owner.version;
}
async function bumpVersion(tx: Tx, userId: string) {
  const [owner] = await tx.update(users).set({ routineVersion: sql`${users.routineVersion} + 1` })
    .where(eq(users.id, userId)).returning({ version: users.routineVersion });
  return owner.version;
}
function unique(ids: string[]) {
  if (new Set(ids).size !== ids.length) fail(400, 'INVALID_PATCH', 'Hay identificadores repetidos.');
}
function cleanName(name: string) {
  const value = name.trim();
  if (!value) fail(400, 'INVALID_NAME', 'El nombre no puede estar vacío.');
  return value;
}

export class RoutineLibrary {
  // Bounded, per-process rate limits; database constraints handle correctness.
  private limits = new Map<string, { until: number; count: number }>();
  constructor(private db: Database) {}
  private rate(userId: string, operation: string, maximum: number, window: number) {
    const key = `${operation}:${userId}`, now = Date.now();
    const previous = this.limits.get(key);
    if (previous && previous.until > now) {
      if (previous.count >= maximum) fail(429, 'RATE_LIMIT', 'Espera un momento antes de intentarlo otra vez.');
      previous.count++;
      return;
    }
    if (this.limits.size >= 10000) {
      for (const [id, value] of this.limits) if (value.until <= now) this.limits.delete(id);
      if (this.limits.size >= 10000) fail(429, 'RATE_LIMIT', 'Espera un momento antes de intentarlo otra vez.');
    }
    this.limits.set(key, { until: now + window, count: 1 });
  }

  async read(userId: string) {
    return this.db.transaction(async (tx) => {
      const [owner] = await tx.select({ version: users.routineVersion }).from(users).where(eq(users.id, userId));
      const rows = await tx.select({
        folderId: routineFolders.id, folderName: routineFolders.name,
        routineId: routines.id, routineName: routines.name, exerciseName: routineExercises.name,
      }).from(routineFolders).leftJoin(routines, eq(routines.folderId, routineFolders.id))
        .leftJoin(routineExercises, eq(routineExercises.routineId, routines.id))
        .where(eq(routineFolders.userId, userId))
        .orderBy(asc(routineFolders.position), asc(routineFolders.id), asc(routines.position), asc(routines.id), asc(routineExercises.position));
      type Routine = { id: string; name: string; exercises: string[] };
      const folders = new Map<string, { id: string; name: string; routines: Routine[] }>();
      const byRoutine = new Map<string, Routine>();
      for (const row of rows) {
        let folder = folders.get(row.folderId);
        if (!folder) { folder = { id: row.folderId, name: row.folderName, routines: [] }; folders.set(row.folderId, folder); }
        if (row.routineId) {
          let routine = byRoutine.get(row.routineId);
          if (!routine) { routine = { id: row.routineId, name: row.routineName!, exercises: [] }; byRoutine.set(row.routineId, routine); folder.routines.push(routine); }
          if (row.exerciseName !== null) routine.exercises.push(row.exerciseName);
        }
      }
      return { version: owner?.version ?? 0, folders: [...folders.values()] };
    }, { isolationLevel: 'repeatable read', accessMode: 'read only' });
  }

  async patch(userId: string, patch: LibraryPatch) {
    unique([...patch.folders.map(f => f.id), ...patch.deletedFolders]);
    unique([...patch.routines.map(r => r.id), ...patch.deletedRoutines]);
    return this.db.transaction(async (tx) => {
      const version = await lockLibrary(tx, userId);
      if (version !== patch.version) fail(409, 'LIBRARY_CHANGED', 'Tus rutinas cambiaron en otra pestaña. Se actualizará la lista; vuelve a realizar el cambio.');
      const folderIds = [...new Set([...patch.folders.map(f => f.id), ...patch.deletedFolders, ...patch.routines.map(r => r.folderId)])];
      const existingFolders = folderIds.length ? await tx.select().from(routineFolders).where(inArray(routineFolders.id, folderIds)) : [];
      if (existingFolders.some(f => f.userId !== userId)) fail(404, 'NOT_FOUND', 'Carpeta no encontrada.');
      const folders = new Map(existingFolders.map(f => [f.id, f]));
      for (const id of patch.deletedFolders) if (!folders.has(id)) fail(404, 'NOT_FOUND', 'Carpeta no encontrada.');
      const routineIds = [...patch.routines.map(r => r.id), ...patch.deletedRoutines];
      const existingRoutines = routineIds.length ? await tx.select({
        id: routines.id, folderId: routines.folderId, name: routines.name, position: routines.position, ownerId: routineFolders.userId,
      }).from(routines).innerJoin(routineFolders, eq(routines.folderId, routineFolders.id)).where(inArray(routines.id, routineIds)) : [];
      if (existingRoutines.some(r => r.ownerId !== userId)) fail(404, 'NOT_FOUND', 'Rutina no encontrada.');
      const savedRoutines = new Map(existingRoutines.map(r => [r.id, r]));
      for (const id of patch.deletedRoutines) if (!savedRoutines.has(id)) fail(404, 'NOT_FOUND', 'Rutina no encontrada.');
      const newFolders = new Set(patch.folders.map(f => f.id));
      for (const routine of patch.routines) {
        if (patch.deletedFolders.includes(routine.folderId) || (!folders.has(routine.folderId) && !newFolders.has(routine.folderId))) {
          fail(404, 'NOT_FOUND', 'Carpeta no encontrada.');
        }
      }
      if (!folderIds.length && !routineIds.length) return { version };
      for (const input of patch.folders) {
        const name = cleanName(input.name), existing = folders.get(input.id);
        if (!existing) await tx.insert(routineFolders).values({ ...input, name, userId });
        else if (existing.name !== name || existing.position !== input.position) await tx.update(routineFolders)
          .set({ name, position: input.position }).where(eq(routineFolders.id, input.id));
      }
      for (const input of patch.routines) {
        const name = cleanName(input.name), existing = savedRoutines.get(input.id);
        if (!existing) await tx.insert(routines).values({ id: input.id, folderId: input.folderId, name, position: input.position });
        else if (existing.name !== name || existing.position !== input.position || existing.folderId !== input.folderId) {
          await tx.update(routines).set({ name, position: input.position, folderId: input.folderId }).where(eq(routines.id, input.id));
        }
        if (input.exercises !== undefined) {
          const names = input.exercises.map(cleanName);
          if (existing) await tx.delete(routineExercises).where(eq(routineExercises.routineId, input.id));
          if (names.length) await tx.insert(routineExercises).values(names.map((name, position) => ({ routineId: input.id, name, position })));
        }
      }
      if (patch.deletedRoutines.length) await tx.delete(routines).where(inArray(routines.id, patch.deletedRoutines));
      if (patch.deletedFolders.length) await tx.delete(routineFolders).where(inArray(routineFolders.id, patch.deletedFolders));
      return { version: await bumpVersion(tx, userId) };
    });
  }

  async recipients(userId: string, query: string) {
    const prefix = query.trim().toLowerCase();
    if (prefix.length < 3 || !/^[a-z0-9@.!#$%&'*+/=?^_`{|}~-]+$/.test(prefix)) return [];
    this.rate(userId, 'search', 30, 60000);
    // Explicit C-collated bounds stay indexable with prepared/generic plans;
    // wildcard characters are literal, and ordering uses this same B-tree.
    const upper = prefix.slice(0, -1) + String.fromCharCode(prefix.charCodeAt(prefix.length - 1) + 1);
    return this.db.select({ id: users.id, email: users.email }).from(users).where(sql`
      ${users.googleSubject} IS NOT NULL AND ${users.email} IS NOT NULL
      AND lower(${users.email}) COLLATE "C" >= ${prefix}
      AND lower(${users.email}) COLLATE "C" < ${upper}
      AND ${users.id} <> ${userId}`)
      .orderBy(sql`lower(${users.email}) COLLATE "C"`).limit(10);
  }

  async send(userId: string, input: { id: string; routineId: string; recipientId: string; version: number }) {
    this.rate(userId, 'send', 20, 3600000);
    if (input.recipientId === userId) fail(400, 'SELF_SHARE', 'Elige otra cuenta para compartir.');
    return this.db.transaction(async (tx) => {
      const version = await lockLibrary(tx, userId);
      const [retry] = await tx.select().from(routineShares).where(eq(routineShares.id, input.id));
      if (retry) {
        if (retry.senderId !== userId || retry.recipientId !== input.recipientId || retry.sourceRoutineId !== input.routineId) fail(409, 'INVALID_REQUEST', 'Identificador de envío ya utilizado.');
        return { id: retry.id, status: retry.status };
      }
      if (version !== input.version) fail(409, 'LIBRARY_CHANGED', 'Actualiza tus rutinas antes de compartir.');
      const [routine] = await tx.select({ id: routines.id, name: routines.name }).from(routines)
        .innerJoin(routineFolders, eq(routines.folderId, routineFolders.id))
        .where(and(eq(routines.id, input.routineId), eq(routineFolders.userId, userId)));
      if (!routine) fail(404, 'NOT_FOUND', 'Rutina no encontrada.');
      const [recipient] = await tx.select({ id: users.id }).from(users).where(sql`
        ${users.id} = ${input.recipientId} AND ${users.googleSubject} IS NOT NULL AND ${users.email} IS NOT NULL`);
      if (!recipient) fail(404, 'RECIPIENT_NOT_FOUND', 'Esta persona debe registrarse primero.');
      const entries = await tx.select({ name: routineExercises.name }).from(routineExercises)
        .where(eq(routineExercises.routineId, routine.id)).orderBy(asc(routineExercises.position)).limit(101);
      if (!entries.length) fail(400, 'EMPTY_ROUTINE', 'Añade ejercicios antes de compartir esta rutina.');
      if (entries.length > 100) fail(400, 'ROUTINE_TOO_LARGE', 'Puedes compartir hasta 100 ejercicios por rutina.');
      const normalizedNames = [...new Set(entries.map(e => normalize(e.name)))];
      const settings = await tx.select().from(exercises).where(and(eq(exercises.userId, userId), inArray(exercises.normalizedName, normalizedNames)));
      const byName = new Map(settings.map(e => [e.normalizedName, e]));
      const snapshot = { version: 1 as const, name: routine.name, exercises: entries.map(e => {
        const config = byName.get(normalize(e.name));
        return { name: e.name, muscleGroup: config?.muscleGroup ?? null, restSeconds: config?.restSeconds ?? 180 };
      }) };
      if (Buffer.byteLength(JSON.stringify(snapshot)) > 60000) fail(400, 'ROUTINE_TOO_LARGE', 'Esta rutina es demasiado grande para compartir.');
      const [share] = await tx.insert(routineShares).values({ id: input.id, senderId: userId, recipientId: input.recipientId,
        sourceRoutineId: routine.id, snapshot, createdAt: new Date() }).onConflictDoNothing().returning({ id: routineShares.id, status: routineShares.status });
      if (share) return share;
      const [pending] = await tx.select({ id: routineShares.id, status: routineShares.status }).from(routineShares)
        .where(and(eq(routineShares.senderId, userId), eq(routineShares.recipientId, input.recipientId), eq(routineShares.sourceRoutineId, routine.id), eq(routineShares.status, 'pending')));
      if (!pending) fail(409, 'INVALID_REQUEST', 'No se pudo crear el envío. Inténtalo de nuevo.');
      return pending;
    });
  }

  async hasPending(userId: string) {
    const [share] = await this.db.select({ id: routineShares.id }).from(routineShares)
      .where(sql`${routineShares.recipientId} = ${userId} AND ${routineShares.status} = 'pending'`).limit(1);
    return { pending: !!share };
  }
  async list(userId: string, direction: 'received' | 'sent', cursor?: string) {
    let before = sql`true`;
    if (cursor) {
      try {
        const value = JSON.parse(Buffer.from(cursor, 'base64url').toString());
        if (typeof value.at !== 'string' || !Number.isFinite(new Date(value.at).getTime()) || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value.id)) throw new Error();
        before = sql`(${routineShares.createdAt}, ${routineShares.id}) < (${new Date(value.at).toISOString()}::timestamptz, ${value.id}::uuid)`;
      } catch { fail(400, 'INVALID_CURSOR', 'Página no válida.'); }
    }
    const sender = alias(users, 'sender'), recipient = alias(users, 'recipient');
    const own = direction === 'received'
      ? sql`${routineShares.recipientId} = ${userId} AND ${routineShares.status} = 'pending'`
      : eq(routineShares.senderId, userId);
    const rows = await this.db.select({
      id: routineShares.id, name: sql<string>`${routineShares.snapshot}->>'name'`,
      exerciseCount: sql<number>`jsonb_array_length(${routineShares.snapshot}->'exercises')`,
      senderEmail: sender.email, recipientEmail: recipient.email,
      status: routineShares.status, createdAt: routineShares.createdAt,
    }).from(routineShares).innerJoin(sender, eq(sender.id, routineShares.senderId))
      .innerJoin(recipient, eq(recipient.id, routineShares.recipientId)).where(and(own, before))
      .orderBy(desc(routineShares.createdAt), desc(routineShares.id)).limit(21);
    const items = rows.slice(0, 20), last = items.at(-1);
    return { items, nextCursor: rows.length > 20 && last ? Buffer.from(JSON.stringify({ at: last.createdAt.toISOString(), id: last.id })).toString('base64url') : null };
  }
  async detail(userId: string, id: string) {
    const [share] = await this.db.select({ id: routineShares.id, snapshot: routineShares.snapshot, status: routineShares.status }).from(routineShares)
      .where(sql`${routineShares.id} = ${id} AND (${routineShares.senderId} = ${userId} OR ${routineShares.recipientId} = ${userId})`);
    if (!share) fail(404, 'NOT_FOUND', 'Envío no encontrado.');
    return share;
  }
  async resolve(userId: string, id: string, action: 'reject' | 'revoke') {
    const target = action === 'reject' ? 'rejected' : 'revoked';
    const owner = action === 'reject' ? routineShares.recipientId : routineShares.senderId;
    return this.db.transaction(async tx => {
      const [share] = await tx.select({ status: routineShares.status }).from(routineShares)
        .where(and(eq(routineShares.id, id), eq(owner, userId))).for('update');
      if (!share) fail(404, 'NOT_FOUND', 'Envío no encontrado.');
      if (share.status === target) return { status: target };
      if (share.status !== 'pending') fail(409, 'SHARE_RESOLVED', 'Este envío ya fue resuelto.');
      await tx.update(routineShares).set({ status: target, resolvedAt: new Date() }).where(eq(routineShares.id, id));
      return { status: target };
    });
  }
  async accept(userId: string, id: string, folderId?: string) {
    return this.db.transaction(async tx => {
      const version = await lockLibrary(tx, userId);
      const [share] = await tx.select().from(routineShares)
        .where(and(eq(routineShares.id, id), eq(routineShares.recipientId, userId))).for('update');
      if (!share) fail(404, 'NOT_FOUND', 'Envío no encontrado.');
      if (share.status === 'accepted') return { routineId: share.importedRoutineId, version, status: 'accepted' };
      if (share.status !== 'pending') fail(409, 'SHARE_RESOLVED', 'Este envío ya fue resuelto.');
      let folder;
      if (folderId) {
        [folder] = await tx.select().from(routineFolders).where(and(eq(routineFolders.id, folderId), eq(routineFolders.userId, userId)));
        if (!folder) fail(404, 'NOT_FOUND', 'Carpeta no encontrada.');
      } else {
        [folder] = await tx.select().from(routineFolders).where(and(eq(routineFolders.userId, userId), eq(routineFolders.name, 'Recibidas'))).limit(1);
        if (!folder) {
          const [position] = await tx.select({ next: sql<number>`coalesce(max(${routineFolders.position}), -1) + 1` }).from(routineFolders).where(eq(routineFolders.userId, userId));
          [folder] = await tx.insert(routineFolders).values({ userId, name: 'Recibidas', position: position.next }).returning();
        }
      }
      const [position] = await tx.select({ next: sql<number>`coalesce(max(${routines.position}), -1) + 1` }).from(routines).where(eq(routines.folderId, folder.id));
      const [copy] = await tx.insert(routines).values({ folderId: folder.id, name: share.snapshot.name, position: position.next }).returning();
      if (share.snapshot.exercises.length) {
        await tx.insert(routineExercises).values(share.snapshot.exercises.map((e, position) => ({ routineId: copy.id, name: e.name, position })));
        const distinct = [...new Map(share.snapshot.exercises.map(e => [normalize(e.name), e])).values()];
        await tx.insert(exercises).values(distinct.map(e => ({ userId, name: e.name, normalizedName: normalize(e.name), muscleGroup: e.muscleGroup, restSeconds: e.restSeconds })))
          .onConflictDoNothing({ target: [exercises.userId, exercises.normalizedName] });
      }
      await tx.update(routineShares).set({ status: 'accepted', importedRoutineId: copy.id, resolvedAt: new Date() }).where(eq(routineShares.id, id));
      return { routineId: copy.id, status: 'accepted', version: await bumpVersion(tx, userId) };
    });
  }
}
