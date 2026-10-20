import { and, asc, desc, eq, inArray, sql } from 'drizzle-orm';
import { alias } from 'drizzle-orm/pg-core';
import { randomUUID } from 'node:crypto';
import type { Database } from './auth.ts';
import { exercises, routineExercises, routineFolders, routines, routineShares, users } from './schema.ts';
import type { RoutineSnapshot, FolderSnapshot } from './schema.ts';

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

  async send(userId: string, input: { id: string; recipientId: string; version: number } & ({ routineId: string } | { folderId: string })) {
    this.rate(userId, 'send', 20, 3600000);
    if (input.recipientId === userId) fail(400, 'SELF_SHARE', 'Elige otra cuenta para compartir.');
    const isFolder = 'folderId' in input;
    const sourceId = isFolder ? input.folderId : input.routineId;
    const sourceColumn = isFolder ? routineShares.sourceFolderId : routineShares.sourceRoutineId;
    return this.db.transaction(async (tx) => {
      const version = await lockLibrary(tx, userId);
      const [retry] = await tx.select().from(routineShares).where(eq(routineShares.id, input.id));
      if (retry) {
        if (retry.senderId !== userId || retry.recipientId !== input.recipientId ||
            (isFolder ? retry.sourceFolderId : retry.sourceRoutineId) !== sourceId ||
            (retry.snapshot.version === 2) !== isFolder) fail(409, 'INVALID_REQUEST', 'Identificador de envío ya utilizado.');
        return { id: retry.id, status: retry.status };
      }
      if (version !== input.version) fail(409, 'LIBRARY_CHANGED', 'Actualiza tus rutinas antes de compartir.');
      let name: string;
      let selected: { id: string; name: string }[];
      if (isFolder) {
        const [folder] = await tx.select({ name: routineFolders.name }).from(routineFolders)
          .where(and(eq(routineFolders.id, sourceId), eq(routineFolders.userId, userId)));
        if (!folder) fail(404, 'NOT_FOUND', 'Carpeta no encontrada.');
        name = folder.name;
        selected = await tx.select({ id: routines.id, name: routines.name }).from(routines)
          .where(eq(routines.folderId, sourceId)).orderBy(asc(routines.position), asc(routines.id)).limit(101);
        if (!selected.length) fail(400, 'EMPTY_FOLDER', 'Añade rutinas antes de compartir esta carpeta.');
        if (selected.length > 100) fail(400, 'FOLDER_TOO_LARGE', 'Puedes compartir hasta 100 rutinas por carpeta.');
      } else {
        selected = await tx.select({ id: routines.id, name: routines.name }).from(routines)
          .innerJoin(routineFolders, eq(routines.folderId, routineFolders.id))
          .where(and(eq(routines.id, sourceId), eq(routineFolders.userId, userId)));
        if (!selected.length) fail(404, 'NOT_FOUND', 'Rutina no encontrada.');
        name = selected[0].name;
      }
      const [recipient] = await tx.select({ id: users.id }).from(users).where(sql`
        ${users.id} = ${input.recipientId} AND ${users.googleSubject} IS NOT NULL AND ${users.email} IS NOT NULL`);
      if (!recipient) fail(404, 'RECIPIENT_NOT_FOUND', 'Esta persona debe registrarse primero.');
      const entries = await tx.select({ routineId: routineExercises.routineId, name: routineExercises.name }).from(routineExercises)
        .where(inArray(routineExercises.routineId, selected.map(r => r.id)))
        .orderBy(asc(routineExercises.routineId), asc(routineExercises.position)).limit(isFolder ? 501 : 101);
      if (!isFolder && !entries.length) fail(400, 'EMPTY_ROUTINE', 'Añade ejercicios antes de compartir esta rutina.');
      if (isFolder && entries.length > 500) fail(400, 'FOLDER_TOO_LARGE', 'Puedes compartir hasta 500 ejercicios por carpeta.');
      const normalizedNames = [...new Set(entries.map(e => normalize(e.name)))];
      const settings = normalizedNames.length ? await tx.select().from(exercises).where(and(eq(exercises.userId, userId), inArray(exercises.normalizedName, normalizedNames))) : [];
      const byName = new Map(settings.map(e => [e.normalizedName, e]));
      const byRoutine = new Map<string, RoutineSnapshot['exercises']>();
      for (const e of entries) {
        const config = byName.get(normalize(e.name));
        const list = byRoutine.get(e.routineId) ?? [];
        list.push({ name: e.name, muscleGroup: config?.muscleGroup ?? null, restSeconds: config?.restSeconds ?? 180 });
        if (list.length > 100) fail(400, 'ROUTINE_TOO_LARGE', 'Puedes compartir hasta 100 ejercicios por rutina.');
        byRoutine.set(e.routineId, list);
      }
      const snapshot: RoutineSnapshot | FolderSnapshot = isFolder
        ? { version: 2, name, routines: selected.map(r => ({ name: r.name, exercises: byRoutine.get(r.id) ?? [] })) }
        : { version: 1, name, exercises: byRoutine.get(selected[0].id) ?? [] };
      if (Buffer.byteLength(JSON.stringify(snapshot)) > 60000) fail(400, isFolder ? 'FOLDER_TOO_LARGE' : 'ROUTINE_TOO_LARGE', 'El contenido es demasiado grande para compartir.');
      const [share] = await tx.insert(routineShares).values({ id: input.id, senderId: userId, recipientId: input.recipientId,
        sourceRoutineId: isFolder ? null : sourceId, sourceFolderId: isFolder ? sourceId : null,
        snapshot, createdAt: new Date() }).onConflictDoNothing().returning({ id: routineShares.id, status: routineShares.status });
      if (share) return share;
      const [pending] = await tx.select({ id: routineShares.id, status: routineShares.status }).from(routineShares)
        .where(and(eq(routineShares.senderId, userId), eq(routineShares.recipientId, input.recipientId), eq(sourceColumn, sourceId), eq(routineShares.status, 'pending')));
      if (!pending) fail(409, 'INVALID_REQUEST', 'No se pudo crear el envío. Inténtalo de nuevo.');
      return pending;
    });
  }

  async hasPending(userId: string, includeFolders = false) {
    const [share] = await this.db.select({ id: routineShares.id }).from(routineShares)
      .where(sql`${routineShares.recipientId} = ${userId} AND ${routineShares.status} = 'pending'
        AND (${includeFolders} OR ${routineShares.snapshot}->>'version' = '1')`).limit(1);
    return { pending: !!share };
  }
  async list(userId: string, direction: 'received' | 'sent', cursor?: string, includeFolders = false) {
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
      kind: sql<string>`CASE WHEN ${routineShares.snapshot}->>'version' = '2' THEN 'folder' ELSE 'routine' END`,
      routineCount: sql<number>`CASE WHEN ${routineShares.snapshot}->>'version' = '2' THEN jsonb_array_length(${routineShares.snapshot}->'routines') ELSE 1 END`,
      exerciseCount: sql<number>`CASE WHEN ${routineShares.snapshot}->>'version' = '2' THEN
        (SELECT coalesce(sum(jsonb_array_length(r->'exercises')), 0)::integer FROM jsonb_array_elements(${routineShares.snapshot}->'routines') r)
        ELSE jsonb_array_length(${routineShares.snapshot}->'exercises') END`,
      senderEmail: sender.email, recipientEmail: recipient.email,
      status: routineShares.status, createdAt: routineShares.createdAt,
    }).from(routineShares).innerJoin(sender, eq(sender.id, routineShares.senderId))
      .innerJoin(recipient, eq(recipient.id, routineShares.recipientId)).where(and(own, before,
        sql`(${includeFolders} OR ${routineShares.snapshot}->>'version' = '1')`))
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
      const isFolder = share.snapshot.version === 2;
      if (share.status === 'accepted') return isFolder
        ? { folderId: share.importedFolderId, version, status: 'accepted' }
        : { routineId: share.importedRoutineId, version, status: 'accepted' };
      if (share.status !== 'pending') fail(409, 'SHARE_RESOLVED', 'Este envío ya fue resuelto.');
      let folder;
      if (isFolder) {
        if (folderId) fail(400, 'INVALID_DESTINATION', 'La carpeta compartida se guarda como una carpeta nueva.');
        const [position] = await tx.select({ next: sql<number>`coalesce(max(${routineFolders.position}), -1) + 1` }).from(routineFolders).where(eq(routineFolders.userId, userId));
        [folder] = await tx.insert(routineFolders).values({ userId, name: share.snapshot.name, position: position.next }).returning();
      } else if (folderId) {
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
      const incoming = share.snapshot.version === 2 ? share.snapshot.routines : [share.snapshot];
      const copies = incoming.map((routine, index) => ({ id: randomUUID(), folderId: folder.id, name: routine.name, position: position.next + index }));
      await tx.insert(routines).values(copies);
      const rows = incoming.flatMap((routine, index) => routine.exercises.map((e, position) => ({ routineId: copies[index].id, name: e.name, position })));
      if (rows.length) await tx.insert(routineExercises).values(rows);
      const allExercises = incoming.flatMap(routine => routine.exercises);
      if (allExercises.length) {
        const distinct = [...new Map(allExercises.map(e => [normalize(e.name), e])).values()];
        await tx.insert(exercises).values(distinct.map(e => ({ userId, name: e.name, normalizedName: normalize(e.name), muscleGroup: e.muscleGroup, restSeconds: e.restSeconds })))
          .onConflictDoNothing({ target: [exercises.userId, exercises.normalizedName] });
      }
      await tx.update(routineShares).set({ status: 'accepted', importedRoutineId: isFolder ? null : copies[0].id,
        importedFolderId: isFolder ? folder.id : null, resolvedAt: new Date() }).where(eq(routineShares.id, id));
      const nextVersion = await bumpVersion(tx, userId);
      return isFolder ? { folderId: folder.id, status: 'accepted', version: nextVersion }
        : { routineId: copies[0].id, status: 'accepted', version: nextVersion };
    });
  }
}
