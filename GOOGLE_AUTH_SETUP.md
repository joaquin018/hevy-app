# Acceso con Google en la PWA

Flutter web usa una cookie HttpOnly del servidor. No guarda tokens en el
almacenamiento del navegador. La API realiza el intercambio OAuth y conserva
solo hashes de los tokens de sesión en PostgreSQL.

## Producción: app.i7l.cl

Proyecto de Google Cloud: **i7l App**, ID `i7l-app-20261014`.
[Abrir Google Auth Platform](https://console.cloud.google.com/auth/overview?project=i7l-app-20261014).
Cliente de tipo Web application: **i7l Web**. Su Client ID y Client Secret se
configuran únicamente en el backend de Dokploy; no se guardan en este repositorio.

Cada cuenta se crea automáticamente al continuar con Google y empieza vacía.
Los datos del antiguo usuario compartido permanecen en la base sin asignarse a
ninguna cuenta nueva. Para mantener este comportamiento, deja
`LEGACY_OWNER_EMAIL` vacío.

1. En [Google Cloud Console](https://console.cloud.google.com/) crea o selecciona
   un proyecto y abre **Google Auth Platform**.
2. Configura **Branding** con el nombre `i7l`, el correo de soporte y el correo
   de contacto. Selecciona audiencia **External**.
3. En **Clients**, crea un cliente de tipo **Web application**.
4. Añade el origen JavaScript `https://app.i7l.cl` y esta URI de retorno exacta:
   `https://app.i7l.cl/api/auth/google/callback`.
5. Guarda el Client ID y el Client Secret en un lugar seguro. Las credenciales
   pertenecen exclusivamente al backend; no las publiques ni las añadas a Git.
6. Si la audiencia está en **Testing**, añade tu cuenta en **Test users**.
   Para permitir el acceso a otras personas, publica la audiencia en producción.

En Dokploy, abre **hevy-app → production → backend → Environment**. Conserva
el `DATABASE_URL` y `PORT` existentes y agrega o actualiza estas variables:

```dotenv
GOOGLE_CLIENT_ID=EL_CLIENT_ID_DE_GOOGLE
GOOGLE_CLIENT_SECRET=EL_CLIENT_SECRET_DE_GOOGLE
GOOGLE_REDIRECT_URI=https://app.i7l.cl/api/auth/google/callback
WEB_ORIGIN=https://app.i7l.cl
LEGACY_OWNER_EMAIL=
SKIP_LOGIN=false
```

Guarda las variables y despliega el backend con el código actualizado; después,
despliega el frontend. El nuevo backend rechaza `SKIP_LOGIN=true` cuando
`WEB_ORIGIN` es el dominio público, por lo que esas variables deben quedar listas
antes del despliegue. Las migraciones son aditivas y conservan los datos existentes.

Verifica en una ventana privada que la app solicita Google y que
`/api/auth/me` devuelve 401 antes del acceso. Entra con dos cuentas diferentes:
ambas deben comenzar vacías y cada una debe conservar únicamente sus rutinas,
ejercicios, sesiones, récords y borradores. Una pestaña abierta con otra cuenta
rechaza lecturas y escrituras cuando detecta que la cookie cambió.

## Desarrollo local

1. Crea un proyecto en Google Cloud y configura Google Auth Platform.
2. Configura el nombre, correo de soporte y audiencia. Si la aplicación está
   en modo de prueba, añade las cuentas que podrán acceder.
3. Crea un cliente de tipo **Web application**.
4. Registra `http://localhost:5173/api/auth/google/callback` como URI de retorno.
5. Configura el `.env` de la raíz:

```dotenv
GOOGLE_CLIENT_ID=tu-client-id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=tu-client-secret
GOOGLE_REDIRECT_URI=http://localhost:5173/api/auth/google/callback
WEB_ORIGIN=http://localhost:5173
LEGACY_OWNER_EMAIL=
SKIP_LOGIN=false
```

En producción sustituye ambas URLs por el dominio HTTPS público y registra
también su URI de retorno en Google Cloud. Las credenciales solo pertenecen al
backend. `/api` debe pasar por Nginx para que las cookies tengan el mismo origen.

Recrea la API después de cambiar las variables:

```bash
docker compose up -d --build api
```

Abre la PWA y pulsa **Continuar con Google**. El navegador vuelve a la app
después de la verificación. Las cookies son HttpOnly, SameSite=Lax y Secure
cuando se utiliza HTTPS. Las sesiones duran 30 días; cerrar sesión revoca el token.

## Datos existentes y acceso temporal

En este despliegue, `LEGACY_OWNER_EMAIL` debe permanecer vacío: ninguna cuenta
nueva recibe los datos del antiguo usuario compartido. Estos datos se conservan
sin asignar. La opción de reclamarlos con un correo verificado existe únicamente
para una migración explícita que se decida en otro momento.

`SKIP_LOGIN=true` permite entrar temporalmente con el usuario de desarrollo,
solo con `WEB_ORIGIN` en localhost, 127.0.0.1 o ::1. Para exigir Google, vuelve
a `false` y recrea la API. No se admite este modo con el dominio público.

## Verificación

La API valida el ID token, el correo verificado, state, nonce y PKCE. Los
intentos duran cinco minutos. Las rutas de datos derivan el usuario de su sesión;
no aceptan un identificador de usuario proporcionado por el cliente.
La migración de autenticación conserva las tablas y datos existentes.

El acceso real debe comprobarse después de configurar las credenciales.

Las pruebas de integración usan identidades de Google simuladas y un esquema
temporal separado; comprueban acceso anónimo, separación entre dos cuentas,
cookies OAuth, caducidad, cierre de sesión y cambios de cuenta entre pestañas.
No sustituyen la comprobación final con Google en producción.

```powershell
# En backend; usar una base de PostgreSQL destinada a pruebas.
$env:TEST_DATABASE_URL='postgres://postgres:CLAVE@localhost:55439/hevy_auth_test'
bun run test
bun run typecheck

# En frontend.
flutter test
flutter analyze
flutter build web --release --no-wasm-dry-run
```

- [Google OAuth para servidores web](https://developers.google.com/identity/protocols/oauth2/web-server)
- [OpenID Connect](https://developers.google.com/identity/openid-connect/openid-connect)
