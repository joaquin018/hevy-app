# Hevy Cloud Stack

Versión actual: **v32**. Consulta el [historial de cambios](CHANGELOG.md) y las
[releases de GitHub](https://github.com/joaquin018/hevy-app/releases).

## Versionado y publicación

El proyecto conserva la numeración de etiquetas anotadas `v1`, `v2`, etc.
Desde `v16`, la versión `vN` corresponde a `N.0.0` en `VERSION` y en
`backend/package.json`, y a `N.0.0+N` en `frontend/pubspec.yaml`.
Los tags anteriores mantienen los archivos y commits históricos originales.
El hash de `deploy-version.json` identifica los archivos de un despliegue y
complementa la versión de Git; no sustituye al tag de la release.

Para publicar otra versión después de terminar los cambios (sustituye `33`
por el siguiente número):

```powershell
bun scripts/version.mjs prepare 33
# Añade una sección ## [v33] con sus cambios y validación a CHANGELOG.md.
bun scripts/version.mjs check v33
# Ejecuta las comprobaciones correspondientes al cambio.
git add VERSION CHANGELOG.md README.md backend/package.json frontend/pubspec.yaml
# Incluye también los archivos de la funcionalidad en el commit.
git commit -m 'chore: prepare release v33'
git tag -a v33 -m 'v33: descripción de los cambios'
git push --atomic origin master v33
bun scripts/version.mjs notes v33 | Set-Content -Encoding utf8 release-notes.tmp.md
gh release create v33 --verify-tag --title 'v33 — descripción de los cambios' --notes-file release-notes.tmp.md --latest
Remove-Item -LiteralPath release-notes.tmp.md
```

Cada release publicada debe tener un tag anotado, manifiestos coherentes y
notas con cambios y validación. No se mueven ni se sobrescriben etiquetas
publicadas. Una corrección posterior recibe una versión nueva. El push
atómico publica el commit y su tag juntos; `--verify-tag` evita que GitHub
cree una etiqueta en un commit diferente.

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

La etapa de compilación ejecuta Flutter con el usuario `flutter` (UID/GID 10001).
El SDK, el proyecto y la caché de Pub pertenecen a ese usuario; la instalación
de paquetes del sistema se realiza antes de cambiar de usuario. Se puede
comprobar la identidad del compilador construyendo esa etapa por separado:

```powershell
docker build --target build -t hevy-flutter-build-check ./frontend
docker run --rm --entrypoint sh hevy-flutter-build-check -c 'test "$(id -u)" -ne 0 && id'
```

La compilación usa BuildKit y separa el SDK de los archivos de la app. Mantiene
cachés de paquetes de Pub y de archivos intermedios de Flutter, identificadas
por versión del SDK y arquitectura, con permisos para el usuario `flutter`.
Para un lockfile ya descargado, las dependencias se validan en modo offline;
si el lockfile es nuevo o faltan paquetes, se descargan respetando ese lockfile.
`flutter build web --no-pub` evita resolver las dependencias una segunda vez.
La resolución y la compilación comparten un paso para funcionar también si
Docker ha limpiado las cachés entre despliegues.

`build/web` se genera fuera de las cachés persistentes. El hash de despliegue,
los archivos de actualización y las cabeceras HTTP se generan como antes, por
lo que una caché de compilación no impide detectar una versión nueva.
Las cachés se conservan en el builder de Docker: el primer despliegue o un
cambio de servidor puede requerir descargar los paquetes de nuevo. No hace
falta configurar volúmenes en Dokploy ni guardar archivos en el navegador.

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

La papelera de cada tarjeta permite eliminar un entrenamiento tras confirmar
su nombre y fecha. Se borran la sesión y sus series, y se reconstruyen los
récords y los valores de `Anterior` usando los entrenamientos restantes.
El historial se recarga para actualizar el contador, los logros y la paginación.
Si falla el borrado, la tarjeta permanece disponible para reintentar.

`DELETE /workout-sessions/:id` requiere autenticación y solo elimina sesiones
de la cuenta actual. El borrado y el recálculo se realizan en una transacción,
coordinada con los guardados simultáneos. Las rutinas, los borradores, las
preferencias de descanso y el catálogo de ejercicios se conservan.

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
No requiere migraciones manuales de la base de datos.

PostgreSQL guarda sesiones, ejercicios y cada serie realizada. La primera
sesión crea el punto de partida. Después, cada posición de serie mantiene su
mejor marca: solo cambia cuando aumenta el peso o aumentan las repeticiones.
Los resultados inferiores permanecen en el historial, pero no reemplazan la
referencia que aparece en la columna `Anterior`.

Cada cuenta accede con Google y utiliza su correo verificado como nombre.
Las cuentas nuevas empiezan sin rutinas ni entrenamientos, con acceso al catálogo
global de ejercicios. Con `LEGACY_OWNER_EMAIL` vacío, los datos personales antiguos
del usuario compartido se conservan sin asignarse a ninguna cuenta nueva.
Rutinas, descansos, borradores, historial y récords se filtran por el usuario
de la sesión autenticada. La API rechaza peticiones de una pestaña que todavía
muestra una cuenta distinta de la cookie actual. Consulta
[la configuración de Google](GOOGLE_AUTH_SETUP.md) para preparar el dominio
`app.i7l.cl`, crear las credenciales y ejecutar las pruebas de aislamiento.

## Comparación de resultados por rutina

En los tres puntos de una rutina, **Comparación de resultados → Aislar resultados**
permite separar sus valores anteriores y récords. Está desactivado por defecto.
Por ejemplo, el press de «Sábado brazos» puede compararse solo con las sesiones
de esa rutina, aunque el mismo ejercicio aparezca el lunes. Un candado en la
tarjeta indica que la opción está activa.

Las rutinas sin aislamiento comparten sus referencias entre sí; las aisladas
usan únicamente sus propias series completadas. Si todavía no tienen resultados,
los campos quedan vacíos. La regla de mejora por peso **o** repeticiones se
mantiene, incluidos los tipos de serie y las W de calentamiento. Editar la rutina,
retomar su borrador y ver los récords del historial respetan la misma separación.

Las nuevas sesiones y borradores guardan el identificador de la rutina, que
permanece al renombrarla o moverla. Al actualizar desde versiones anteriores,
la migración automática asocia una sola vez los nombres coincidentes, ignorando
mayúsculas y espacios exteriores, que sean únicos dentro de la cuenta. Los
nombres duplicados, renombrados antes de esta actualización o sin coincidencia
quedan sin asociar y conservan la comparación compartida. No se importan las
marcas globales como base de una rutina aislada: se releen sus series reales.

Activar o desactivar la opción recalcula las referencias y los logros de sus
sesiones anteriores, sin borrar el historial. Se debe terminar o descartar un
entrenamiento en curso de esa rutina antes de cambiar la opción. Una rutina
eliminada conserva la identidad de sus sesiones; las copias recibidas al compartir
tienen un identificador nuevo y empiezan con el aislamiento desactivado.

La API admite `isolateResults` en `PATCH /routine-library`, `routineId` en los
guardados de sesiones y borradores, y `routineId` como parámetro opcional de
`GET /exercises/previous`. Se valida la propiedad de la rutina. Los clientes
antiguos deben recargar la app antes de guardar una rutina aislada; la API devuelve
`428 ROUTINE_UPGRADE_REQUIRED` para evitar guardados con referencias compartidas.

## Catálogo global de ejercicios

Los ejercicios creados por cualquier cuenta aparecen en **Agregar ejercicio**
para todos los usuarios. Se pueden buscar y seleccionar directamente, o actualizar
el catálogo deslizando hacia abajo. Solo se comparten el nombre y el grupo muscular;
los pesos, las repeticiones, las marcas y el descanso siguen siendo personales.
El formulario de creación explica qué información estará disponible para todos.

Al iniciar, el backend crea `exercise_catalog` e incorpora también los ejercicios
existentes. La migración conserva los identificadores de los ejercicios personales
y sus referencias a sesiones y récords. Las altas posteriores, los entrenamientos
guardados y las importaciones de rutinas o carpetas alimentan el mismo catálogo.

Los nombres se deduplican ignorando mayúsculas y espacios al principio o al final.
Se conserva la primera descripción publicada; si falta el grupo muscular, una
aportación posterior puede completarlo. El catálogo permanece aunque se elimine
la cuenta que creó el ejercicio. `GET /exercises` y `POST /exercises` mantienen
el formato `{ name, muscleGroup }` y requieren autenticación.

## Compartir rutinas y carpetas dentro de i7l

En las opciones de una rutina, **Compartir rutina** busca el correo de una
cuenta registrada. La búsqueda comienza con tres caracteres, espera 350 ms
al escribir y devuelve hasta diez coincidencias. Solo muestra identificador
y correo; requiere sesión y tiene un límite de 30 consultas por minuto por
cuenta. El prefijo se trata literalmente, incluidos `%` y `_`.

El botón de bandeja abre **Compartidos**, con recibidas y enviadas.
El destinatario ve una vista previa y acepta en una carpeta propia o en
**Recibidas**, creada automáticamente. Puede rechazar; el remitente puede
cancelar mientras el envío esté pendiente. No se envían correos ni se necesita
un servicio adicional. Para recibir, la persona debe registrarse primero.

En las opciones de una carpeta, **Compartir carpeta** envía todas sus rutinas
en un solo envío. La vista previa muestra las rutinas y sus ejercicios en orden.
Al aceptar, se crea una carpeta nueva con el nombre original y copias independientes
de todas las rutinas, incluidas las que todavía no tienen ejercicios. Editar o
eliminar la carpeta original después del envío no cambia la copia recibida.
Se conservan los grupos musculares y descansos; la configuración que el
destinatario ya tenga para un ejercicio tiene prioridad. No se comparten sesiones
ni récords personales.

`POST /folder-shares` usa la misma selección de destinatario, control de versión,
reintentos y límite de envíos que una rutina individual. Admite hasta 100 rutinas,
100 ejercicios por rutina y 500 por carpeta, dentro del límite de tamaño del envío.
La migración agrega referencias de carpeta e índices sin reemplazar los envíos
existentes. Las bandejas y el aviso incluyen carpetas con `includeFolders=true`;
las pestañas anteriores siguen recibiendo únicamente rutinas individuales.

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
