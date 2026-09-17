# Acceso con Google en la PWA

Flutter web usa una cookie HttpOnly del servidor. No guarda tokens en el
almacenamiento del navegador. La API realiza el intercambio OAuth y conserva
solo hashes de los tokens de sesión en PostgreSQL.

## Configuración

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

Antes del primer acceso, configura `LEGACY_OWNER_EMAIL` con el correo que
recibirá los datos del usuario de desarrollo. Solo esa identidad verificada
puede reclamarlos. Sin esta variable, las nuevas cuentas empiezan sin datos.
Las cuentas ya creadas requieren una migración explícita para fusionar datos.

`SKIP_LOGIN=true` permite entrar temporalmente con el usuario de desarrollo.
Para exigir Google, vuelve a `false` y recrea la API.

## Verificación

La API valida el ID token, el correo verificado, state, nonce y PKCE. Los
intentos duran cinco minutos. Las rutas de datos derivan el usuario de su sesión;
no aceptan un identificador de usuario proporcionado por el cliente.
La migración de autenticación conserva las tablas y datos existentes.

El acceso real debe comprobarse después de configurar las credenciales.

- [Google OAuth para servidores web](https://developers.google.com/identity/protocols/oauth2/web-server)
- [OpenID Connect](https://developers.google.com/identity/openid-connect/openid-connect)
