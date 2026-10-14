# Historial de versiones de i7l

Las etiquetas `vN` identifican versiones completas del proyecto. Cada etiqueta
publicada conserva su commit; los cambios posteriores reciben otra versión.
Las fechas siguientes corresponden al cambio versionado. `v14` y `v15` se
etiquetaron retrospectivamente el 14 de octubre de 2026.

## [v16] — 2026-10-14

Compartir rutinas entre cuentas registradas dentro de i7l.

- Buscar destinatarios por correo, con al menos tres caracteres y hasta diez coincidencias.
- Bandejas de rutinas recibidas y enviadas, vista previa, aceptación, rechazo y cancelación.
- Copias independientes que conservan los ejercicios y su configuración, sin compartir historial ni récords.
- Identificadores estables y guardado de cambios individuales con control de versión.
- Índices de búsqueda y bandeja, paginación y límites de frecuencia.
- Alineación de `VERSION`, backend y Flutter con la versión publicada.

Validación de la funcionalidad: 23 pruebas del backend y 11 del frontend,
análisis estático y compilación web correctos. Consultas verificadas con
50.000 cuentas y más de 50.000 envíos en una base desechable.

Implementación: [9e4dafe](https://github.com/joaquin018/hevy-app/commit/9e4dafea31e6255b3c8bce4537618192b5cb0989).
[Cambios desde v15](https://github.com/joaquin018/hevy-app/compare/v15...v16).

## [v15] — 2026-10-14

Cuentas privadas con inicio de sesión de Google.

- Registro y acceso con el correo verificado de Google.
- Rutinas, ejercicios, borradores, historial y récords separados por cuenta.
- Protección del retorno OAuth, del estado de sesión y de peticiones de pestañas con otra cuenta.
- Las cuentas nuevas empiezan vacías; los datos compartidos antiguos permanecen sin asignar.
- El modo de acceso local queda limitado a localhost.

Validación: 10 pruebas de integración y 4 pruebas del cliente de autenticación,
análisis estático y compilación web correctos.

Commit: [54fc4f9](https://github.com/joaquin018/hevy-app/commit/54fc4f924eab43cbc1a8c45d7858cb459e316c59).
[Cambios desde v14](https://github.com/joaquin018/hevy-app/compare/v14...v15).

## [v14] — 2026-09-17

Compilación de Flutter y despliegue en Dokploy.

- Compilar Flutter desde el código durante la construcción de Docker.
- Preparar el frontend, backend y PostgreSQL para Dokploy.
- Actualizaciones de la PWA y versiones de los archivos compilados.
- Documentación del entorno y del despliegue.

Commit: [ffbbfba](https://github.com/joaquin018/hevy-app/commit/ffbbfba1a7d6517871257f7a73e02312e4ce2ada).
[Cambios desde v13](https://github.com/joaquin018/hevy-app/compare/v13...v14).

## Versiones anteriores

Las etiquetas originales `v1` a `v13` se conservan sin modificaciones. Sus
anotaciones y commits están disponibles en [las etiquetas de GitHub](https://github.com/joaquin018/hevy-app/tags).
