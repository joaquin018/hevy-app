# Hevy Cloud Stack

Stack mínimo:

- Flutter + Riverpod + HTTP, sin base de datos local.
- Elysia + TypeScript + Drizzle sobre Bun 1.4.2, como runtime y gestor de dependencias.
- PostgreSQL 18.6 como única fuente de datos.
- Cloudflare Tunnel opcional.

## Historial de entrenamientos

PostgreSQL guarda sesiones, ejercicios y cada serie realizada. La primera
sesión crea el punto de partida. Después, cada posición de serie mantiene su
mejor marca: solo cambia cuando aumenta el peso o aumentan las repeticiones.
Los resultados inferiores permanecen en el historial, pero no reemplazan la
referencia que aparece en la columna `Anterior`.

Durante el desarrollo se usa el usuario fijo
`00000000-0000-4000-8000-000000000001`. El esquema ya separa los datos por
usuario para conectar autenticación posteriormente.

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

Para ejecutar todo en Docker:

```bash
docker compose up --build -d
curl http://localhost:3000/health
```

### Migración desde PostgreSQL 17

PostgreSQL 18 usa el volumen `postgres18_data`, montado en
`/var/lib/postgresql`. El volumen anterior `postgres_data` se conserva como
respaldo; no se puede reutilizar directamente como directorio de PostgreSQL 18.
En otras instalaciones con datos en PostgreSQL 17, detén la API y exporta la
base con `pg_dump -Fc` y los roles con `pg_dumpall --roles-only` antes de cambiar
el contenedor. Restaura primero los roles (omitiendo la creación de roles que
ya existan) y luego la base con `pg_restore` en una base vacía de PostgreSQL 18.
Comprueba los datos antes de iniciar la API. Un volumen nuevo sin restauración
inicia una base vacía.

En el entorno local, la migración del 8 de septiembre de 2026 conserva el
volumen `hevy-app_postgres_data` y los respaldos en `backups/` (excluidos de Git).
Se verificaron los conteos de las 11 tablas tras restaurar datos y roles.

Para guardar una sesión:

```bash
curl -X POST http://localhost:3000/workout-sessions \
  -H "content-type: application/json" \
  -d '{"routineName":"Lunes","startedAt":"2026-08-07T20:00:00Z","completedAt":"2026-08-07T20:45:00Z","durationSeconds":2700,"exercises":[{"name":"Press Banca Inclinado Con Barra","muscleGroup":"Pecho","sets":[{"type":"normal","kg":40,"reps":6,"completed":true}]}]}'
```

Para consultar la última ejecución de un ejercicio:

```bash
curl "http://localhost:3000/exercises/previous?name=Press%20Banca%20Inclinado%20Con%20Barra"
```

## Flutter

```bash
cd frontend
flutter pub get
flutter run
```

Flutter lee y escribe siempre mediante la API. El emulador Android usa
`http://10.0.2.2:3000` automáticamente y las aplicaciones de escritorio usan
`http://localhost:3000`.

Para un dispositivo físico indica una URL accesible desde el teléfono:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:3000
```

## Cloudflare Tunnel (opcional)

1. Crea un túnel en Cloudflare y copia su token.
2. Copia `.env.example` a `.env` y reemplaza el token.
3. Asocia un hostname público a `http://api:3000`.
4. Ejecuta `docker compose --profile tunnel up --build -d`.

No publiques PostgreSQL (`5432`) en producción. La app debe conectarse a la API,
nunca directamente a la base de datos.
