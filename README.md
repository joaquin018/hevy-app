# Hevy Cloud Stack

Stack mínimo:

- Flutter + Riverpod + HTTP, sin base de datos local.
- Elysia + TypeScript + Drizzle sobre Bun, con dependencias administradas por pnpm.
- PostgreSQL como única fuente de datos.
- Cloudflare Tunnel opcional.

## API y PostgreSQL

```bash
docker compose up --build -d
curl http://localhost:3000/health
curl http://localhost:3000/hello
```

Para guardar otro saludo:

```bash
curl -X POST http://localhost:3000/hello \
  -H "content-type: application/json" \
  -d '{"message":"Hola desde Docker"}'
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
