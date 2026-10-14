import { createHash, randomBytes } from 'node:crypto';
import { OAuth2Client, CodeChallengeMethod } from 'google-auth-library';
import { Elysia, t } from 'elysia';
import { and, eq, gt, lt, isNull, or } from 'drizzle-orm';
import { drizzle } from 'drizzle-orm/postgres-js';
import { authSessions, loginAttempts, users } from './schema.ts';

export type Database = ReturnType<typeof drizzle>;
export type AuthConfig = { clientId: string; clientSecret: string; redirectUri: string; legacyOwnerEmail?: string; webOrigin?: string; skipLogin?: boolean };
export type GoogleIdentity = { subject: string; email: string };
export type GoogleProvider = {
  authorizationUrl(state: string, nonce: string, challenge: string): string;
  exchange(code: string, verifier: string, nonce: string): Promise<GoogleIdentity>;
};
export const tokenHash = (value: string) => createHash('sha256').update(value).digest('hex');
const randomToken = () => randomBytes(32).toString('base64url');
const legacyUserId = '00000000-0000-4000-8000-000000000001';

export function validateAuthConfig(config: AuthConfig) {
  if (!config.skipLogin) return;
  let origin: URL | undefined;
  try { origin = new URL(config.webOrigin ?? ''); } catch { /* Fail closed below. */ }
  if (!origin || !['http:', 'https:'].includes(origin.protocol) ||
      !['localhost', '127.0.0.1', '[::1]'].includes(origin.hostname)) {
    throw new Error('SKIP_LOGIN=true solo se permite en desarrollo con WEB_ORIGIN en localhost. Usa SKIP_LOGIN=false en el dominio público.');
  }
}

export function readCookie(header: string | undefined, name: string) {
  return header?.split(';').map(part => part.trim()).find(part => part.startsWith(`${name}=`))?.slice(name.length + 1);
}
export function requestAuthorization(headers: Record<string, string | undefined>) {
  const token = readCookie(headers.cookie, 'i7l_session');
  return headers.authorization ?? (token ? `Bearer ${token}` : undefined);
}
export function rejectCrossOrigin(request: Request, config: AuthConfig) {
  if (['GET', 'HEAD', 'OPTIONS'].includes(request.method)) return false;
  const origin = request.headers.get('origin');
  const expected = config.webOrigin ?? new URL(request.url).origin;
  return (origin !== null && origin !== expected) || request.headers.get('sec-fetch-site') === 'cross-site';
}
const browserCookie = (name: string, value: string, maxAge: number, config: AuthConfig) =>
  `${name}=${value}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAge}${config.webOrigin?.startsWith('https:') ? '; Secure' : ''}`;

export function googleProvider(config: AuthConfig): GoogleProvider {
  const oauth = new OAuth2Client(config.clientId, config.clientSecret, config.redirectUri);
  return {
    authorizationUrl: (state, nonce, challenge) => oauth.generateAuthUrl({
      scope: ['openid', 'email'], state, nonce, prompt: 'select_account',
      code_challenge: challenge, code_challenge_method: CodeChallengeMethod.S256,
    }),
    async exchange(code, verifier, nonce) {
      const { tokens } = await oauth.getToken({ code, codeVerifier: verifier });
      if (!tokens.id_token) throw new Error('Missing Google identity');
      const ticket = await oauth.verifyIdToken({ idToken: tokens.id_token, audience: config.clientId });
      const payload = ticket.getPayload();
      if (!payload?.sub || !payload.email || !payload.email_verified ||
          (payload as unknown as { nonce?: string }).nonce !== nonce) throw new Error('Invalid Google identity');
      return { subject: payload.sub, email: payload.email.toLowerCase() };
    },
  };
}

export async function authenticate(db: Database, authorization?: string, skipLogin = false) {
  if (skipLogin) {
    const [user] = await db.select({ id: users.id, email: users.email }).from(users)
      .where(eq(users.id, legacyUserId)).limit(1);
    return user ? { id: user.id, email: user.email ?? 'local@i7l.test', tokenHash: '' } : null;
  }
  const match = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(authorization ?? '');
  if (!match) return null;
  const [session] = await db.select({ id: users.id, email: users.email, tokenHash: authSessions.tokenHash })
    .from(authSessions).innerJoin(users, eq(users.id, authSessions.userId))
    .where(and(eq(authSessions.tokenHash, tokenHash(match[1]!)), gt(authSessions.expiresAt, new Date()))).limit(1);
  return session?.email ? session : null;
}

export function authRoutes(db: Database, config: AuthConfig, provider = googleProvider(config)) {
  const configured = Boolean(config.clientId && config.clientSecret && config.redirectUri);
  const starts = new Map<string, { count: number; until: number }>();
  const app = new Elysia().onRequest(({ request, status, set }) => {
    set.headers['cache-control'] = 'no-store';
    if (rejectCrossOrigin(request, config)) return status(403, { message: 'Origen no permitido.' });
  }).get('/health', () => ({ status: 'ok' }));
  app.post('/auth/google/start', async ({ status, server, request, set }) => {
    if (!configured) return status(503, { message: 'El acceso con Google aún no está configurado.' });
    const isWeb = new URL(request.url).searchParams.get('web') === '1';
    if (isWeb && (!config.webOrigin || new URL(config.redirectUri).origin !== config.webOrigin)) {
      return status(503, { message: 'Configura WEB_ORIGIN y GOOGLE_REDIRECT_URI con el mismo origen del frontend web.' });
    }
    const now = Date.now();
    for (const [key, bucket] of starts) if (bucket.until <= now) starts.delete(key);
    const ip = server?.requestIP(request)?.address ?? 'local';
    const bucket = starts.get(ip) ?? { count: 0, until: now + 5 * 60_000 };
    if (bucket.count >= 30 || starts.size >= 10000) return status(429, { message: 'Espera unos minutos antes de volver a intentarlo.' });
    bucket.count++;
    starts.set(ip, bucket);
    await db.delete(loginAttempts).where(lt(loginAttempts.expiresAt, new Date()));
    await db.delete(authSessions).where(lt(authSessions.expiresAt, new Date()));
    const attemptToken = randomToken();
    const state = randomToken();
    const nonce = randomToken();
    const verifier = randomToken();
    await db.insert(loginAttempts).values({ tokenHash: tokenHash(attemptToken), state, nonce, verifier, browserFlow: isWeb,
      expiresAt: new Date(Date.now() + 5 * 60_000) });
    const challenge = createHash('sha256').update(verifier).digest('base64url');
    const authorizationUrl = provider.authorizationUrl(state, nonce, challenge);
    if (isWeb) {
      set.headers['set-cookie'] = browserCookie('i7l_login', attemptToken, 300, config);
      return { authorizationUrl };
    }
    return { attemptToken, authorizationUrl };
  });
  app.get('/auth/google/callback', async ({ query, set, headers }) => {
    set.headers['content-type'] = 'text/html; charset=utf-8';
    set.headers['referrer-policy'] = 'no-referrer';
    set.headers['content-security-policy'] = "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'";
    const page = (message: string) => `<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>i7l · Google</title><body style="background:#090b0f;color:white;font:18px system-ui;padding:48px;max-width:600px;margin:auto"><h1>i7l</h1><p>${message}</p></body></html>`;
    const browserAttempt = readCookie(headers.cookie, 'i7l_login');
    const [attempt] = await db.update(loginAttempts).set({ status: 'processing' })
      .where(and(eq(loginAttempts.state, query.state ?? ''), eq(loginAttempts.status, 'pending'), gt(loginAttempts.expiresAt, new Date()),
        or(eq(loginAttempts.browserFlow, false), eq(loginAttempts.tokenHash, tokenHash(browserAttempt ?? '')))))
      .returning();
    if (!attempt) { set.status = 400; return page('Este acceso caducó o ya se utilizó. Vuelve a la app para intentarlo de nuevo.'); }
    try {
      if (!configured || query.error || !query.code) throw new Error('Google login denied');
      const identity = await provider.exchange(query.code, attempt.verifier, attempt.nonce);
      await db.transaction(async (tx) => {
        let [account] = await tx.select().from(users).where(eq(users.googleSubject, identity.subject));
        // Only an explicitly configured owner may claim the existing development data.
        if (!account && config.legacyOwnerEmail?.toLowerCase() === identity.email) {
          [account] = await tx.update(users).set({ googleSubject: identity.subject, email: identity.email, displayName: identity.email })
            .where(and(eq(users.id, legacyUserId), isNull(users.googleSubject))).returning();
        }
        if (!account) {
          [account] = await tx.insert(users).values({ googleSubject: identity.subject, email: identity.email, displayName: identity.email })
            .onConflictDoUpdate({ target: users.googleSubject, set: { email: identity.email, displayName: identity.email } }).returning();
        } else {
          await tx.update(users).set({ email: identity.email, displayName: identity.email }).where(eq(users.id, account.id));
        }
        await tx.update(loginAttempts).set({ userId: account!.id, status: 'ready', verifier: '' })
          .where(eq(loginAttempts.tokenHash, attempt.tokenHash));
      });
      if (attempt.browserFlow && config.webOrigin) {
        const token = randomToken();
        await db.transaction(async tx => {
          const [ready] = await tx.delete(loginAttempts)
            .where(and(eq(loginAttempts.tokenHash, attempt.tokenHash), eq(loginAttempts.status, 'ready'))).returning();
          if (!ready?.userId) throw new Error('Login already consumed');
          await tx.insert(authSessions).values({ tokenHash: tokenHash(token), userId: ready.userId, expiresAt: new Date(Date.now() + 30 * 86400_000) });
        });
        set.headers['set-cookie'] = [browserCookie('i7l_session', token, 30 * 86400, config), browserCookie('i7l_login', '', 0, config)];
        set.status = 303;
        set.headers.location = `${config.webOrigin}/`;
        return '';
      }
      return page('Cuenta verificada. Ya puedes cerrar esta pestaña y volver a la app.');
    } catch {
      await db.update(loginAttempts).set({ status: 'failed', verifier: '' }).where(eq(loginAttempts.tokenHash, attempt.tokenHash));
      set.status = 400;
      return page('No se pudo completar el acceso con Google. Vuelve a la app e inténtalo de nuevo.');
    }
  }, { query: t.Object({ state: t.Optional(t.String({ maxLength: 256 })), code: t.Optional(t.String({ maxLength: 4096 })), error: t.Optional(t.String({ maxLength: 256 })) }) });
  app.post('/auth/google/finish', async ({ body, status }) => {
    const hash = tokenHash(body.attemptToken);
    return db.transaction(async (tx) => {
      const [attempt] = await tx.select().from(loginAttempts).where(eq(loginAttempts.tokenHash, hash)).for('update');
      if (!attempt || attempt.expiresAt <= new Date()) return status(410, { message: 'El acceso ha caducado.' });
      if (attempt.status === 'failed') return status(401, { message: 'Google no pudo verificar la cuenta.' });
      if (attempt.status !== 'ready' || !attempt.userId) return status(202, { pending: true });
      const [account] = await tx.select().from(users).where(eq(users.id, attempt.userId));
      const token = randomToken();
      await tx.insert(authSessions).values({ tokenHash: tokenHash(token), userId: account!.id, expiresAt: new Date(Date.now() + 30 * 86400_000) });
      await tx.delete(loginAttempts).where(eq(loginAttempts.tokenHash, hash));
      return { token, user: { id: account!.id, email: account!.email } };
    });
  }, { body: t.Object({ attemptToken: t.String({ pattern: '^[A-Za-z0-9_-]{43}$' }) }) });
  app.post('/auth/google/cancel', async ({ body }) => {
    await db.delete(loginAttempts).where(eq(loginAttempts.tokenHash, tokenHash(body.attemptToken)));
    return { cancelled: true };
  }, { body: t.Object({ attemptToken: t.String({ pattern: '^[A-Za-z0-9_-]{43}$' }) }) });
  app.get('/auth/me', async ({ headers, status }) => {
    const user = await authenticate(db, requestAuthorization(headers), config.skipLogin);
    return user ? { id: user.id, email: user.email } : status(401, { message: 'Inicia sesión para continuar.' });
  });
  app.delete('/auth/session', async ({ headers, set }) => {
    const user = await authenticate(db, requestAuthorization(headers));
    if (user) await db.delete(authSessions).where(eq(authSessions.tokenHash, user.tokenHash));
    set.headers['set-cookie'] = browserCookie('i7l_session', '', 0, config);
    return { signedOut: true };
  });
  return app;
}
