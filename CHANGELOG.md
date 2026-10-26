# Historial de versiones de i7l

Las etiquetas `vN` identifican versiones completas del proyecto. Cada etiqueta
publicada conserva su commit; los cambios posteriores reciben otra versión.
Las fechas siguientes corresponden al cambio versionado. `v14` y `v15` se
etiquetaron retrospectivamente el 14 de octubre de 2026.

## [v32] — 2026-10-26

Aislar los resultados y récords de una rutina de forma opcional.

- Añadir «Comparación de resultados → Aislar resultados» al menú de cada rutina, desactivado por defecto, con un indicador en su tarjeta.
- Usar las series completadas de esa rutina para sus valores anteriores y récords, incluidos los entrenamientos previos identificables y las series de calentamiento.
- Guardar el identificador de la rutina en sesiones y borradores para conservar la separación al renombrarla, moverla o retomar el entrenamiento.
- Asociar una sola vez el historial anterior por nombres únicos dentro de la cuenta; conservar sin asociar los nombres ambiguos o sin coincidencia.
- Recalcular las referencias y los logros al cambiar la opción o eliminar una sesión, sin perder el historial ni mezclar rutinas aisladas con la comparación compartida.
- Impedir cambios de comparación mientras haya un entrenamiento en curso de esa rutina y validar la propiedad de los identificadores en la API.
- Mantener independientes las copias recibidas al compartir y añadir índices para consultar las series de la rutina.
- Alineación de `VERSION`, backend y Flutter con la versión publicada.

Validación: 58 pruebas del backend y 47 del frontend, comprobación de tipos,
análisis estático y compilación web correctos. Verificados la migración desde
v31, el historial anterior, los permisos, los cambios concurrentes, el borrado,
las copias compartidas y la recuperación de borradores. Consulta de series
mediante índice comprobada con 10.000 sesiones de otra cuenta.

[Cambios desde v31](https://github.com/joaquin018/hevy-app/compare/v31...v32).

## [v31] — 2026-10-26

Optimizar la compilación del frontend en Docker.

- Separar el SDK de Flutter de los archivos de la aplicación.
- Conservar cachés de paquetes de Pub y de archivos intermedios, por versión del SDK y arquitectura.
- Resolver dependencias desde la caché cuando sea posible, manteniendo la validación estricta del lockfile y descargando los paquetes que falten.
- Evitar la segunda resolución de dependencias con `flutter build web --no-pub`.
- Mantener la compilación sin root y la generación del contenido web y del identificador de actualización.
- Alineación de `VERSION`, backend y Flutter con la versión publicada.

Validación: compilaciones Docker con cachés vacías y calientes, incluida una
versión con código distinto compilada sin red. Comprobados el contenido nuevo,
las cabeceras sin caché del identificador y el aviso de actualización entre versiones.
Las compilaciones con caché vacía y caliente produjeron el mismo contenido.

[Cambios desde v30](https://github.com/joaquin018/hevy-app/compare/v30...v31).

## [v30] — 2026-10-26

Fondo opaco en la confirmación de borrado del historial.

- Usar un fondo sólido en «Eliminar entrenamiento» para evitar que el historial se vea a través del diálogo.
- Alineación de `VERSION`, backend y Flutter con la versión publicada.

Validación: 8 pruebas de eliminación del historial y análisis estático de la
pantalla correctos.

[Cambios desde v29](https://github.com/joaquin018/hevy-app/compare/v29...v30).

## [v29] — 2026-10-26

Compilar Flutter en Docker con un usuario sin privilegios de root.

- Crear el usuario y grupo `flutter` con UID/GID 10001 y utilizarlo antes de instalar y ejecutar Flutter.
- Asignarle la propiedad del SDK, el proyecto y la caché de Pub, incluidos los archivos copiados al contenedor.
- Resolver la causa de la alerta de superusuario sin añadir opciones para ocultarla.
- Documentar cómo comprobar la identidad del usuario de compilación.
- Alineación de `VERSION`, backend y Flutter con la versión publicada.

Validación: compilación Docker completa, UID/GID 10001 y propiedad y permisos
de los archivos comprobados. Imagen final de Nginx verificada con configuración
válida, respuestas HTTP 200 y generación correcta de la versión de despliegue.

[Cambios desde v28](https://github.com/joaquin018/hevy-app/compare/v28...v29).

## [v28] — 2026-10-26

Eliminar entrenamientos desde el historial.

- Añadir una papelera en cada sesión con confirmación de su nombre y fecha antes de borrarla.
- Eliminar la sesión y sus series, y recalcular los récords y los valores de `Anterior` con los entrenamientos restantes.
- Actualizar el contador, los logros y la paginación después del borrado, con avisos de error y posibilidad de reintentar.
- Restringir el borrado a la cuenta propietaria y coordinarlo con los guardados simultáneos en una transacción.
- Conservar rutinas, borradores, preferencias de descanso y catálogo de ejercicios.
- Alineación de `VERSION`, backend y Flutter con la versión publicada.

Validación: 45 pruebas del backend y 43 del frontend, comprobación de tipos,
análisis estático y compilación web correctos. Verificados los permisos, el
recálculo de referencias, los cambios concurrentes y la reversión ante errores
en una base desechable; cancelación, reintentos y paginación probados en la interfaz.

[Cambios desde v27](https://github.com/joaquin018/hevy-app/compare/v27...v28).

## [v27] — 2026-10-24

Simplificar la cabecera del historial.

- Eliminar el texto motivacional «Cada entrenamiento cuenta.» y su espacio adicional.
- Alineación de `VERSION`, backend y Flutter con la versión publicada.

Validación: análisis estático de la pantalla de historial sin errores.

[Cambios desde v26](https://github.com/joaquin018/hevy-app/compare/v26...v27).

## [v26] — 2026-10-24

Más opciones para el temporizador de descanso.

- Ofrecer nueve duraciones cada 30 segundos, desde 1 min hasta 5 min.
- Añadir 1 min 30s, 2 min 30s, 3 min 30s y 4 min 30s al selector.
- Conservar la duración en segundos al guardar, cargar y empezar el descanso.
- Mantener los tiempos intermedios al salir y retomar el entrenamiento.
- Alineación de `VERSION`, backend y Flutter con la versión publicada.

Validación: 35 pruebas del frontend, análisis estático y compilación web correctos.
Verificados el guardado y el inicio de las nueve duraciones, además de la carga
y la persistencia del descanso de 1 min 30s al retomar el entrenamiento.

[Cambios desde v25](https://github.com/joaquin018/hevy-app/compare/v25...v26).

## [v25] — 2026-10-24

Mostrar los resultados anteriores al editar una rutina.

- Cargar las series y los resultados personales también en «Editar rutina».
- Mostrar los pesos y las repeticiones anteriores, incluidos los calentamientos con su marca W.
- Conservar una serie vacía editable cuando el ejercicio todavía no tiene resultados.
- Mantener la edición sin iniciar un entrenamiento ni guardar borradores o sesiones.
- Alineación de `VERSION`, backend y Flutter con la versión publicada.

Validación: 33 pruebas del frontend, análisis estático y compilación web correctos.
La prueba de regresión reproduce el fallo original y verifica la carga de cuatro
series, incluidos dos calentamientos.

[Cambios desde v24](https://github.com/joaquin018/hevy-app/compare/v24...v25).

## [v24] — 2026-10-23

Catálogo global de ejercicios para todas las cuentas.

- Compartir el nombre y el grupo muscular de los ejercicios creados por cualquier usuario.
- Incorporar automáticamente los ejercicios existentes sin modificar sus identificadores ni el historial personal.
- Mantener separados por cuenta los pesos, las repeticiones, los récords y los tiempos de descanso.
- Alimentar el catálogo desde la creación de ejercicios, los entrenamientos y las importaciones de rutinas o carpetas.
- Evitar duplicados por mayúsculas o espacios y permitir actualizar el catálogo deslizando hacia abajo.
- Alineación de `VERSION`, backend y Flutter con la versión publicada.

Validación: 36 pruebas del backend y 31 del frontend, comprobación de tipos,
análisis estático y compilación web correctos. Migración, uso entre cuentas
y creación concurrente verificados en una base desechable.

[Cambios desde v23](https://github.com/joaquin018/hevy-app/compare/v23...v24).

## [v23] — 2026-10-23

Rellenar los resultados anteriores al completar una serie.

- Copiar el peso y las repeticiones del placeholder a los campos vacíos al marcar el check.
- Conservar los valores introducidos, incluidos los decimales con coma y el peso cero.
- Guardar los campos rellenados en el borrador y la sesión sin duplicar el volumen al desmarcar y volver a marcar.
- Alineación de `VERSION`, backend y Flutter con la versión publicada.

Validación: 29 pruebas del frontend, análisis estático y compilación web correctos.

[Cambios desde v22](https://github.com/joaquin018/hevy-app/compare/v22...v23).

## [v22] — 2026-10-20

Fondo de inicio uniforme con el icono de la aplicación.

- Usar `#0d1017`, el color de fondo del icono, en el arranque de la PWA.
- Unificar el fondo y el color de tema del manifiesto y la página inicial para integrar el logotipo.
- Alineación de `VERSION`, backend y Flutter con la versión publicada.

Validación: coincidencia de colores comprobada en ambos iconos, el manifiesto
y la página inicial; compilación web correcta.

[Cambios desde v21](https://github.com/joaquin018/hevy-app/compare/v21...v22).

## [v21] — 2026-10-20

Compartir carpetas completas entre cuentas registradas.

- Opción «Compartir carpeta» con selección de destinatario por correo.
- Vista previa de todas las rutinas y ejercicios, y aceptación como una carpeta nueva con copias independientes.
- Conservar el nombre, el orden y la configuración de ejercicios sin compartir sesiones ni récords personales.
- Bandeja unificada de rutinas y carpetas, reintentos sin duplicados y controles de acceso entre cuentas.
- Migración aditiva e índices de carpetas, compatibles con los envíos existentes y las pestañas anteriores.
- Alineación de `VERSION`, backend y Flutter con la versión publicada.

Validación: 30 pruebas del backend y 24 del frontend, comprobación de tipos,
análisis estático y compilación web correctos. Migración y copias verificadas
en una base desechable, incluida la aceptación concurrente y la paginación.

[Cambios desde v20](https://github.com/joaquin018/hevy-app/compare/v20...v21).

## [v20] — 2026-10-20

Placeholder de correo más claro al compartir rutinas.

- Mostrar «Ej.: persona@gmail.com» en gris y cursiva para distinguirlo del correo ingresado.
- Mantener visible la etiqueta «Correo de Google» cuando el campo está vacío.
- Alineación de `VERSION`, backend y Flutter con la versión publicada.

Validación: 7 pruebas de compartir rutinas, análisis estático y compilación web correctos.

[Cambios desde v19](https://github.com/joaquin018/hevy-app/compare/v19...v20).

## [v19] — 2026-10-20

Las series de calentamiento conservan la marca W.

- Recuperar el tipo de las series anteriores y conservarlo al guardar o retomar el entrenamiento.
- Mantener las selecciones del usuario cuando el historial llega con retraso.
- Mostrar el tipo de serie junto a la medalla de récord y permitir volver a una serie normal con su número correcto.
- Evitar series duplicadas al cargar las referencias anteriores.
- Alineación de `VERSION`, backend y Flutter con la versión publicada.

Validación: 21 pruebas del frontend, análisis estático y compilación web correctos.

[Cambios desde v18](https://github.com/joaquin018/hevy-app/compare/v18...v19).

## [v18] — 2026-10-20

El descanso continúa al salir de la pantalla de entrenamiento.

- Conservar el temporizador y los ajustes de ±15 segundos al retroceder y retomar el entrenamiento.
- Calcular el tiempo restante desde la hora de finalización, incluido el tiempo fuera de la pantalla o en segundo plano.
- Evitar que un descanso terminado se reinicie o que un entrenamiento nuevo herede el anterior.
- Alineación de `VERSION`, backend y Flutter con la versión publicada.

Validación: 16 pruebas del frontend, análisis estático y compilación web correctos.

[Cambios desde v17](https://github.com/joaquin018/hevy-app/compare/v17...v18).

## [v17] — 2026-10-20

Búsqueda de ejercicios con o sin tildes.

- Ignorar tildes, diéresis y mayúsculas al buscar por nombre de ejercicio o grupo muscular.
- Admitir acentos Unicode combinados y conservar los nombres originales al mostrar y seleccionar resultados.
- Alineación de `VERSION`, backend y Flutter con la versión publicada.

Validación: 11 pruebas del frontend, análisis estático y compilación web correctos.

[Cambios desde v16](https://github.com/joaquin018/hevy-app/compare/v16...v17).

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
