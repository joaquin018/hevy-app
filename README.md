# Hevy Cloud Stack

Stack mínimo:

- Flutter + Riverpod + HTTP, sin base de datos local.
- Elysia + TypeScript + Drizzle sobre Bun, con dependencias administradas por pnpm.
- PostgreSQL como única fuente de datos.
- Cloudflare Tunnel opcional.

## Historial de entrenamientos

PostgreSQL guarda sesiones, ejercicios y cada serie realizada. La primera
sesión crea el punto de partida; las siguientes consultan el último peso y las
repeticiones registradas para completar la columna `Anterior`.

Durante el desarrollo se usa el usuario fijo
`00000000-0000-4000-8000-000000000001`. El esquema ya separa los datos por
usuario para conectar autenticación posteriormente.

## API y PostgreSQL

```bash
docker compose up --build -d
curl http://localhost:3000/health
```

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
