# EmuChull

EmuChull es una aplicación de escritorio escrita en Flutter que funciona como lanzador/emulador de consolas (interfaz tipo consola).
Ofrece opciones de configuración, gestión de emuladores, controles, audio y un instalador de Windows para distribuir la aplicación.

Este README cubre qué hace la aplicación, cómo preparar un entorno de desarrollo, pasos para compilar en Windows, cómo generar el instalador y notas técnicas útiles para mantenimiento.

## Características principales

- Interfaz de usuario pensada para escritorio (Windows, Linux, macOS) con navegación por teclado/mando.
- Gestión y lanzamiento de emuladores (estructura para integrar distintos backends).
- Panel de ajustes con control de audio, resolución, modo ventana/pantalla completa, música de menú, controles, y opciones de restablecer/aplicar.
- Soporte para reproducir música de fondo y controlar volúmenes (maestro, música, SFX).
- Sistema de persistencia de configuración (SettingsService) y carga de resoluciones detectadas.
- Scripts y configuración para generar un instalador de Windows (Inno Setup) en `installer/`.

## Estado del proyecto

- Lenguaje: Dart + Flutter (desktop targets).
- Branch actual: `main`.
- Nota: Algunas APIs de Flutter en el proyecto aparecen como obsoletas (por ejemplo `RawKeyboardListener`, `RawKeyEvent`). El código funciona pero puede requerir actualizaciones para eliminar warnings deprecados.

## Requisitos (desarrollo)

Para compilar y ejecutar localmente necesitas:

- Flutter SDK (estable) y configuración para targets de escritorio. Asegúrate de tener `flutter` en PATH.
- Visual Studio (para build Windows) o los requisitos de Flutter Desktop en Windows (Windows build tools).
- Inno Setup (ISCC.exe) si quieres generar el instalador (*.iss script) — instalar desde https://jrsoftware.org/
- Opcional: ImageMagick (`magick`) si deseas convertir PNG a ICO desde el script de instalador.
- Opcional: Windows SDK / signtool.exe si quieres firmar el instalador (.pfx).

## Ejecutar en modo desarrollo

1. Clona el repositorio y sitúate en la raíz del proyecto.
2. Instala dependencias:

```powershell
flutter pub get
```

3. Ejecuta la app en modo debug (por ejemplo para Windows):

```powershell
flutter run -d windows
```

4. Para ejecutar análisis estático:

```powershell
flutter analyze
```

Observación: `flutter analyze` en este repo muestra advertencias relacionadas con APIs deprecadas y uso de BuildContext a través de gaps async. Son avisos que conviene corregir progresivamente.

## Compilar release para Windows

1. Asegúrate de tener configurado el entorno de build para Windows (Visual Studio y workloads necesarios).
2. Ejecuta:

```powershell
flutter build windows --release
```

El ejecutable de la aplicación se generará en `build\windows\x64\runner\Release\`.

## Generar el instalador de Windows (.exe)

El repositorio incluye un script PowerShell y un script de Inno Setup para empaquetar la aplicación en un instalador.

1. Requisitos previos:
	 - Inno Setup (ISCC.exe) instalado y en la ubicación esperada por el script, o ajusta el path en `installer/build_installer.ps1`.
	 - (Opcional) ImageMagick (`magick`) si el icono `.ico` se debe generar a partir de un `.png`.
	 - (Opcional) `signtool.exe` y un certificado `.pfx` si quieres firmar el instalador.

2. Añade tu icono en `assets/icons/` (por ejemplo `APP.ico` o `emuchull.ico`). El script copiará el `.ico` a `windows/runner/resources/app_icon.ico` antes de compilar.

3. Ejecuta el script desde la carpeta `installer` (PowerShell):

```powershell
cd installer
.\build_installer.ps1
```

El script realiza (resumen):
- copia/convierte el icono a `windows/runner/resources/app_icon.ico`
- ejecuta `flutter build windows --release`
- invoca `ISCC.exe` con la plantilla `.iss` para empaquetar los ficheros en un instalador
- (opcional) firma el instalador si configuras variables para `signtool` y un `.pfx` valido

Salida esperada: `installer/Output/EMUCHULLSetup_x64.exe` (nombre y ruta según la plantilla `.iss`).

Si hay errores en la compilación o el script no encuentra `ISCC.exe`, ajusta las rutas dentro de `installer/build_installer.ps1`.

## Estructura del proyecto (resumen)

- `lib/` — código Dart/Flutter principal
	- `main.dart` — entrypoint
	﻿# EmuChull — Documentación completa y guía para desarrolladores

	Este README explica en detalle la arquitectura, los componentes, las clases y flujos principales de la aplicación EmuChull (Flutter Desktop). Está escrito en español y pensado para que cualquier desarrollador que reciba este repositorio entienda cómo funciona la aplicación, qué hace cada módulo y cómo realizar cambios sin romper funcionalidades existentes.

	Si vas a trabajar en este proyecto, empieza por leer `main.dart`, `lib/services/profile_service.dart` y `lib/services/input_service.dart` para comprender la inicialización, la persistencia de perfiles y el sistema de entrada (gamepad/teclado).

	---

	## Resumen / Propósito

	EmuChull es un frontend orientado a emuladores. Sus funciones principales son:

	- Gestión de perfiles de usuario (avatares empaquetados o importados, opción de PIN privado).
	- Gestión de emuladores y su librería de juegos (escaneo o añadidos manualmente).
	- Lanzamiento de emuladores y juegos con navegación tipo consola (soporte para gamepad/teclado).
	- Reproducción de efectos de sonido (SFX) y música de fondo persistente.

	La app está optimizada para escritorio (Windows, con adaptaciones para otras plataformas) y usa plugins nativos para vídeo/audio cuando están disponibles (`dart_vlc`, `audioplayers`).

	---

	## Estructura del proyecto (alto nivel)

	- `lib/` — código fuente:
		- `main.dart` — inicializaciones globales y arranque de la app.
		- `models/` — modelos de dominio (`Profile`, `EmulatorData`, `GameData`).
		- `screens/` — pantallas UI (login, perfiles, emulador, ajustes).
		- `services/` — singletons con lógica de negocio y persistencia (AudioService, ProfileService, InputService, SettingsService, EmulatorManager, etc.).
		- `widgets/` — componentes visuales reutilizables (keyboard, cards, dialogs).
		- `ui/` — utilidades y temas.
	- `assets/` — imágenes, sonidos y videos empaquetados.
	- `installer/`, `windows/`, `macos/`, `linux/` — scripts y recursos específicos de plataforma.

	---

	## Dependencias clave (extraídas de `pubspec.yaml`)

	- `audioplayers` — reproducción de SFX y música de fondo.
	- `dart_vlc` — opcional, usado para fondo en vídeo (requiere libVLC instaladas o bundling).
	- `file_picker`, `path_provider` — para importar avatares y escribir en documentos de la app.
	- `window_manager`, `win32`, `win32_gamepad` — funcionalidades específicas de escritorio y gamepad en Windows.
	- `shared_preferences` — persistencia simple de la lista de perfiles.

	---

	## Documentación de módulos y clases (detallada)

	Abajo se describen los módulos más importantes. Cada sección indica responsabilidades, contratos, formatos de datos y notas para quien vaya a modificar el código.

	### `lib/main.dart`

	- Función: arranque de la aplicación. Inicializa librerías nativas, servicios y la ventana.
	- Tareas importantes:
		- Inicializa `DartVLC` con varias estrategias para localizar libVLC (carpeta `windows/vlc`, carpeta junto al exe, Program Files). Intenta varias firmas de `DartVLC.initialize` dinámicamente.
		- Inicializa `window_manager` y aplica tamaño/modo fullscreen según `SettingsService`.
		- Llama `AudioService.instance.init()` y `InputService.instance.initialize()`.
		- Ejecuta `runApp(MyApp())`.

	Notas para cambios: si integras otro plugin nativo, añade fallbacks para no romper la inicialización en máquinas donde ese plugin no esté disponible.

	### Modelos (en `lib/models` y `lib/models/*.dart`)

	- GameData
		- Campos: `path`, `displayName`, `coverUrl`.
		- Uso: representa un juego en la librería de un emulador.

	- EmulatorData
		- Campos principales: `name`, `exePath`, `supportedExts`, `games`, `coverPath`, `launchArgs`, `workingDirectory`, `manualAddsOnly`, `launchFullscreen`.
		- Uso: representa la configuración de un emulador y su lista de juegos. Serializable a JSON con `toJson()` y reconstruible con `fromJson()`.

	- Profile
		- Campos: `id`, `name`, `avatarPath`, `isPrivate`, `pinHash`, `emulatorIds`, `gamePaths`, `gamesByEmulator`.
		- `avatarPath` puede ser:
			- `asset:assets/avatars/xxx.png` — avatar empaquetado.
			- Ruta absoluta en disco — avatar importado.
		- Persistencia: `ProfileService` serializa la lista completa de perfiles.

	### `ProfileService` (`lib/services/profile_service.dart`)

	- Singleton: `ProfileService.instance`.
	- Responsabilidades:
		- Cargar perfiles desde `SharedPreferences` (clave `_kProfilesKey`).
		- Guardar perfiles (serializa lista a JSON).
		- `hashPin(pin)` produce SHA-256 con salt interno.
		- Utilities: `setProfileGamesForEmulator`, `getProfileGamesForEmulator`, `normalizeProfileEmulatorIds`, `removeEmulatorFromAllProfiles`.

	Contratos y consideraciones:
	- `loadProfiles()` hace migraciones simples y devuelve una lista vacía ante errores (protección frente a perfiles corruptos).
	- Evita acceder a `SharedPreferences` en tight loops; trabaja con copias y guarda cuando haya cambios significativos.

	### `AudioService` (`lib/services/audio_service.dart`)

	- Singleton: `AudioService.instance`.
	- Manejo de recursos:
		- Players: `_nav`, `_action`, `_launch`, `_bgMusic`.
		- `init()` crea los players y registra listeners en `SettingsService` para sincronizar volúmenes y pistas.
		- `_applyBgFromSettings()` mantiene la reproducción de background music según `SettingsService.audio.bgMusicPath` y `SettingsService.bgMusicEnabled`.
		- `resetBgOnLogout()` resetea `_bgCurrentPath` y detiene la música para que al entrar de nuevo el bg empiece desde 0.

	Buenas prácticas:
	- Para cambiar la pista background sin reiniciar la posición, el servicio comprueba `_bgCurrentPath`. Si la misma ruta sigue activa, hace `resume()`; si cambió la ruta, hace `seek(Duration.zero)`.
	- Si la app debe reiniciar la música al cambiar perfil, asegúrate de invocar `resetBgOnLogout()` en el flujo de logout.

	### `InputService` (`lib/services/input_service.dart`)

	- Rol: abstraer entradas (gamepad/teclado) a eventos de alto nivel.
	- API: `pushListener(InputListener)` que devuelve una `VoidCb` para removerlo.
	- Nota crítica: listeners son apilables; cada `pushListener()` debe tener su `remove` posterior para no acumular eventos. Usa `try { remove?.call(); }` en `finally`.

	### Emuladores (`EmulatorManager`, `EmulatorRunner`, `EmulatorHelper`)

	- `EmulatorManager`: mantiene la lista de emuladores y provee operaciones CRUD sobre `EmulatorData`.
	- `EmulatorRunner`: inicia procesos nativos del emulador con argumentos y working directory; tiene hooks para pausar la música de fondo y restaurarla.
	- `EmulatorHelper`: utilidades para escaneo y validación de juegos.

	### Screens / Widgets

	- `emuchull_login.dart`: pantalla principal de selección/creación de perfiles. Implementa:
		- Grilla de perfiles (tarjetas con avatar y nombre).
		- Diálogo `Crear perfil`: lee `AssetManifest.json` para mostrar `assets/avatars/` y permite importar desde disco (copia a `getApplicationDocumentsDirectory()`).
		- Uso de `FocusableActionDetector` y `InputService` para navegación por gamepad.
	- `profile_home.dart` y `profile_emulator_home.dart`: pantallas interiores tras seleccionar perfil.
	- `emulator_screen.dart`: pantalla donde se ejecuta el emulador con overlay de controles.
	- Widgets en `lib/widgets`: `onscreen_keyboard.dart`, `emulator_card.dart`, `emulator_game_grid.dart`, `emulator_dialogs.dart`.

	---

	## Formatos de datos y ejemplos

	Ejemplo de `Profile` serializado:

	```json
	{
		"id": "163287...",
		"name": "David",
		"avatarPath": "asset:assets/avatars/ralph.jpg",
		"isPrivate": false,
		"pinHash": null,
		"emulatorIds": ["emu1","emu2"],
		"gamePaths": [],
		"gamesByEmulator": {"emu1": ["C:/roms/game.iso"]}
	}
	```

	`EmulatorData` y `GameData` usan `toJson()`/`fromJson()` y son fácilmente serializables.

	---

	## Flujos de uso (detallado)

	1. Inicio
		 - `main()` intenta inicializar `DartVLC` y `window_manager`.
		 - `SettingsService.instance.load()` carga preferencias (ventana, volúmenes, paths).
		 - `AudioService.init()` crea players y aplica volúmenes.
		 - `InputService.initialize()` prepara detección de gamepads.

	2. Pantalla de perfiles
		 - `ProfileService.loadProfiles()` carga perfiles desde `SharedPreferences`.
		 - La pantalla muestra una tarjeta para crear perfil (ícono + texto) y tarjetas para cada perfil guardado.
		 - Seleccionar 'Crear perfil' abre un diálogo que lee `AssetManifest.json` para listar avatares empaquetados y permite importar desde disco.

	3. Crear perfil
		 - Validaciones: nombre no vacío; avatar seleccionado (asset o importado); si `Privado` está activado, PIN de 4 dígitos.
		 - Persistencia: se genera un `id` único y se llama a `ProfileService.saveProfiles()`.

	4. Lanzar emulador
		 - `Profile` seleccionado -> `ProfileEmulatorHomeScreen` muestra emuladores asociados.
		 - Al lanzar juego: `AudioService.pauseBgMusic()` (opcional) y `EmulatorRunner.launch()`.
		 - Al cerrar emulador: `AudioService.resumeBgMusic()`.

	---

	## Casos borde y recomendaciones prácticas

	- Archivos grandes (instaladores): evita añadir ejecutables al repo; usa Git LFS o `releases` en GitHub.
	- Input listeners: asegura `removeListener()` cuando se cierra un diálogo para evitar pérdidas de control.
	- Assets: si cambias la convención de `avatarPath`, actualiza todos los renderers que chequean `startsWith('asset:')`.
	- Manejo de errores: muchos servicios capturan excepciones y hacen `debugPrint`. Para producción, implementar logging centralizado.

	---

	## Guía rápida para nuevos desarrolladores

	1. Hacer un fork/clone y ejecutar `flutter pub get`.
	2. Ejecutar `flutter analyze`.
	3. Ejecutar `flutter run -d windows` para pruebas interactivas (si trabajas en Windows).
	4. Antes de hacer PRs:
		 - Formatear: `flutter format .`
		 - Ejecutar `flutter analyze`.
		 - Probar flujos de UI principales: creación de perfil, importación de avatar, lanzamiento de emulador.

	---

	## Siguientes mejoras recomendadas (prioridad)

	1. Añadir tests unitarios para `ProfileService` (serialización, migraciones) — alto impacto.
	2. Añadir tests/mocks para `AudioService` y `InputService`.
	3. Extraer el diálogo de crear perfil a un widget separado y testable.
	4. Mover instaladores grandes fuera del repo o usar Git LFS.

	---

	Si deseas, genero también:

	- Documentación archivo por archivo (cada clase con ejemplos de uso).
	- Comentarios estilo `dartdoc` dentro de cada servicio (añadir docstrings).
	- Tests unitarios de ejemplo que cubran `ProfileService` y las rutas de avatar.

	Fin del README.
