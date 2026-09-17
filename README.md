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
- `docker-compose.yml` y `postgres-init.sql`: servicios e inicialización de datos.

Flutter genera `.dart_tool` y `build`; no se versionan. Los respaldos locales
están fuera del repositorio en `C:\0Antigravity\hevy-app-db-backups`.

### Ejecutar la versión web

```powershell
cd frontend
flutter pub get
flutter build web --release
cd ..
docker compose up -d --build api web
```

Abre http://localhost:5173. Después de modificar Dart, repite la compilación y
`docker compose up -d --build web`. El contenedor sirve `frontend/build/web`:
el SDK Flutter se utiliza localmente y no hace falta dentro de Nginx.

La web usa `/api` en el mismo origen y Google usa cookies HttpOnly.
Configura `WEB_ORIGIN=http://localhost:5173`
y `GOOGLE_REDIRECT_URI=http://localhost:5173/api/auth/google/callback` en `.env`.
Consulta [GOOGLE_AUTH_SETUP.md](GOOGLE_AUTH_SETUP.md).

`SKIP_LOGIN=true` en la API conserva el acceso temporal con el usuario local.
Para exigir Google, cambia a `false` y recrea el servicio `api`.

La PWA incluye manifiesto e iconos para instalarla desde el navegador con HTTPS
(o localhost). Necesita conexión para cargar y guardar datos. El worker no
almacena respuestas privadas ni ofrece uso sin conexión. Las actualizaciones
se cargan al reabrir o recargar; no se fuerza una recarga durante un entrenamiento.

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
Rutinas, ejercicios, borradores, historial y récords se filtran por el usuario
de la sesión autenticada. Consulta [la configuración de Google](GOOGLE_AUTH_SETUP.md)
para crear las credenciales y asignar explícitamente los datos de desarrollo.

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
