# Hevy Cloud Stack

## Aplicación Flutter

Flutter es la única interfaz, distribuida como web/PWA.
Las pantallas están en `frontend/lib`; `frontend/web` contiene solo la entrada
web, el manifiesto y los iconos. La API Elysia y PostgreSQL conservan los datos.

Estructura:

- `frontend/lib/*.dart`: pantallas, autenticación, modelos y cliente API.
- `frontend/web`: arranque, manifiesto e iconos de la PWA.
- `frontend/assets`: recursos de la aplicación.
- `backend/*.ts`: API, esquema y migración.
- `backend/init.sql`: inicialización automática e idempotente de la base.
- `docker-compose.yml`: entorno local opcional.

Flutter genera `.dart_tool` y `build`; no se versionan. Los respaldos locales
están fuera del repositorio en `C:\0Antigravity\hevy-app-db-backups`.

### Ejecutar la versión web

```powershell
docker compose up -d --build api web
```

Abre http://localhost:5173. Después de modificar Dart, ejecuta
`docker compose up -d --build web`. Docker compila Flutter desde el código;
la imagen final solo contiene Nginx y la aplicación compilada.

La web usa `/api` en el mismo origen y Google usa cookies HttpOnly.
Configura `WEB_ORIGIN=http://localhost:5173`
y `GOOGLE_REDIRECT_URI=http://localhost:5173/api/auth/google/callback` en `.env`.
Consulta [GOOGLE_AUTH_SETUP.md](GOOGLE_AUTH_SETUP.md).

`SKIP_LOGIN=true` en la API conserva el acceso temporal con el usuario local,
solo si `WEB_ORIGIN` apunta a localhost.
Para exigir Google, cambia a `false` y recrea el servicio `api`.

La PWA incluye manifiesto e iconos para instalarla desde el navegador con HTTPS
(o localhost). Necesita conexión para cargar y guardar datos. El worker no
almacena respuestas privadas ni ofrece uso sin conexión. Las actualizaciones
se cargan al reabrir o recargar; no se fuerza una recarga durante un entrenamiento.
Mientras está abierta, comprueba nuevas versiones cada minuto y al volver a
primer plano. Muestra un botón para actualizar después de guardar los cambios.
El identificador de versión se genera en Docker a partir del contenido compilado.

## Dokploy: dos Applications y PostgreSQL

Usa el mismo repositorio y rama para ambas Applications, con build type Dockerfile.

| Application | Dockerfile Path | Docker Context Path | Puerto interno |
| --- | --- | --- | --- |
| frontend | frontend/Dockerfile | frontend | 80 |
| backend | backend/Dockerfile | backend | 3000 |

En `db`, crea PostgreSQL con almacenamiento persistente. Copia su URL interna
a `DATABASE_URL` del backend. La API crea las tablas al arrancar, bajo un bloqueo
transaccional, sin borrar datos existentes. No hace falta importar SQL a mano.

Variables del backend:

```dotenv
DATABASE_URL=postgresql://USUARIO:CLAVE@HOST_INTERNO_DB:5432/BASE
PORT=3000
WEB_ORIGIN=https://gym.example.com
GOOGLE_REDIRECT_URI=https://gym.example.com/api/auth/google/callback
GOOGLE_CLIENT_ID=CLIENT_ID
GOOGLE_CLIENT_SECRET=CLIENT_SECRET
SKIP_LOGIN=false
```

Variable del frontend:

```dotenv
BACKEND_ORIGIN=http://NOMBRE_INTERNO_APPLICATION_BACKEND:3000
```

Usa el nombre interno real de Dokploy, sin barra final ni `/api`. Los tres
servicios deben poder comunicarse por la red interna de Dokploy. Asigna el
dominio público y HTTPS solo al frontend, puerto 80; no publiques PostgreSQL.
Registra la URI de retorno en Google Cloud. Despliega primero db, luego backend
y finalmente frontend. `/api/health` debe devolver `{"status":"ok"}`.

Para probar sin Google en localhost, `SKIP_LOGIN=true` da acceso al usuario local.
El backend rechaza este modo con un `WEB_ORIGIN` público.
No migra datos desde tu PC: si quieres conservarlos, restaura un respaldo en db.

Activa Auto Deploy/webhook para ambas Applications si quieres que un push a
la rama configurada publique los cambios. La PWA detecta el nuevo frontend
después de un despliegue exitoso; un push por sí solo no cambia la app instalada.
Conserva compatibilidad de la API con pestañas que aún usen la versión anterior.
No configures una CDN para ignorar las cabeceras `Cache-Control` del servidor.

Referencias: [Flutter web y caché](https://docs.flutter.dev/platform-integration/web/faq),
[Applications de Dokploy](https://docs.dokploy.com/docs/core/applications).

### Validación

```powershell
cd frontend
flutter analyze
flutter build web --release
```

## Historial de entrenamientos

El botón Historial de la cabecera de Rutinas abre las sesiones, de la más
reciente a la más antigua, con fecha y hora local, duración, volumen y récords.
Cada tarjeta permite mostrar todos los ejercicios y desplegar pesos,
repeticiones y tipo de serie. Se puede actualizar deslizando hacia abajo.

`GET /workout-sessions?offset=0&limit=20` devuelve `sessions`, `total` y
`hasMore`. El volumen suma peso × repeticiones de las series completadas,
incluidas las de calentamiento. Los récords cuentan series que mejoraron
peso o repeticiones frente a su referencia anterior; la primera aparición
establece la referencia y no cuenta como récord.

Para recuperar también los logros de sesiones existentes, el servidor
reconstruye las referencias en orden de guardado antes de paginar. Así un
récord posterior no borra el logro de una sesión anterior. Esta primera
implementación lee el historial del usuario completo para calcularlos; si
crece mucho, conviene persistir los logros por serie y paginar en SQL.
No requiere migración de la base de datos.

PostgreSQL guarda sesiones, ejercicios y cada serie realizada. La primera
sesión crea el punto de partida. Después, cada posición de serie mantiene su
mejor marca: solo cambia cuando aumenta el peso o aumentan las repeticiones.
Los resultados inferiores permanecen en el historial, pero no reemplazan la
referencia que aparece en la columna `Anterior`.

Cada cuenta accede con Google y utiliza su correo verificado como nombre.
Las cuentas nuevas empiezan vacías. Con `LEGACY_OWNER_EMAIL` vacío, los datos
antiguos del usuario compartido se conservan sin asignarse a ninguna cuenta nueva.
Rutinas, ejercicios, borradores, historial y récords se filtran por el usuario
de la sesión autenticada. La API rechaza peticiones de una pestaña que todavía
muestra una cuenta distinta de la cookie actual. Consulta
[la configuración de Google](GOOGLE_AUTH_SETUP.md) para preparar el dominio
`app.i7l.cl`, crear las credenciales y ejecutar las pruebas de aislamiento.

## Compartir rutinas dentro de i7l

En las opciones de una rutina, **Compartir rutina** busca el correo de una
cuenta registrada. La búsqueda comienza con tres caracteres, espera 350 ms
al escribir y devuelve hasta diez coincidencias. Solo muestra identificador
y correo; requiere sesión y tiene un límite de 30 consultas por minuto por
cuenta. El prefijo se trata literalmente, incluidos `%` y `_`.

El botón de bandeja abre **Rutinas compartidas**, con recibidas y enviadas.
El destinatario ve una vista previa y acepta en una carpeta propia o en
**Recibidas**, creada automáticamente. Puede rechazar; el remitente puede
cancelar mientras el envío esté pendiente. No se envían correos ni se necesita
un servicio adicional. Para recibir, la persona debe registrarse primero.

Cada envío conserva una instantánea de nombre, ejercicios ordenados, grupo
muscular y descanso. La aceptación crea una copia independiente sin historial,
series ni récords, y conserva la configuración de ejercicios que el destinatario
ya tenga. Reintentar un envío o aceptar dos veces no duplica la rutina.

`routine_shares` relaciona cuentas por UUID, con índices para la bandeja del
destinatario, enviados, duplicados pendientes y claves foráneas. La búsqueda
usa un B-tree sobre `lower(email) COLLATE "C"`, con límites explícitos de prefijo
que también funcionan con planes preparados. La bandeja pagina 20 resultados
mediante fecha e identificador; el contenido se consulta al abrir la vista previa.
El aviso consulta existencia de pendientes al abrir/volver a la app y cada
minuto cuando la pantalla principal está visible. Los límites de búsqueda y
envío (20 por hora) son por proceso; si se despliegan varias réplicas deberán
coordinarse en el servidor de entrada o en un almacén compartido.

Las carpetas y rutinas mantienen UUID estables. `GET /routine-library` devuelve
la biblioteca y su versión; `PATCH /routine-library` recibe únicamente cambios
y eliminaciones explícitas. Un bloqueo de fila por cuenta y la versión evitan
sobrescribir cambios entre pestañas o una rutina recién aceptada. Las lecturas
usan dos consultas coherentes, evitando una consulta por rutina. La migración
es aditiva y conserva los datos existentes. Las pestañas antiguas pueden seguir
leyendo `GET /routine-folders`; el antiguo `PUT` pide recargar antes de guardar.

Pruebas en una base desechable, nunca en producción:

```powershell
$env:TEST_DATABASE_URL='postgres://USUARIO:CLAVE@localhost:PUERTO/BASE_DE_PRUEBAS'
cd backend
bun run typecheck
bun test
cd ../frontend
flutter test
flutter analyze
flutter build web --release
```

Las pruebas crean y eliminan esquemas aislados. Cubren privacidad, permisos,
copias, reintentos, cambios concurrentes, paginación y planes de ejecución con
50.000 cuentas y 50.000 envíos. Los tiempos de esa prueba no representan una
garantía de rendimiento en producción.

## API y PostgreSQL

Para desarrollar el backend localmente con Bun 1.4.2:

```bash
docker compose up -d postgres
cd backend
bun install --frozen-lockfile
bun run typecheck
bun run dev
```

`bun.lock` fija las dependencias para desarrollo y Docker. `bun run start`
ejecuta la API sin recarga automática. La API usa el puerto 3000; detén la
API de Docker con `docker compose stop api` antes de ejecutarla localmente.

`bun run dev` carga el único `.env` de la raíz. Docker recibe esas variables
mediante Compose.

Para ejecutar todo en Docker:

```bash
cd frontend
flutter build web --release
cd ..
docker compose up --build -d
curl http://localhost:3000/health
```

Para guardar una sesión:

```bash
curl -X POST http://localhost:3000/workout-sessions \
  -H "Authorization: Bearer $SESSION_TOKEN" \
  -H "content-type: application/json" \
  -d '{"routineName":"Lunes","startedAt":"2026-08-07T20:00:00Z","completedAt":"2026-08-07T20:45:00Z","durationSeconds":2700,"exercises":[{"name":"Press Banca Inclinado Con Barra","muscleGroup":"Pecho","sets":[{"type":"normal","kg":40,"reps":6,"completed":true}]}]}'
```

Para consultar la última ejecución de un ejercicio:

```bash
curl -H "Authorization: Bearer $SESSION_TOKEN" "http://localhost:3000/exercises/previous?name=Press%20Banca%20Inclinado%20Con%20Barra"
```
