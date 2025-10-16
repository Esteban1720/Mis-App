# EmuChull (Playstations)

EmuChull es una aplicación de escritorio escrita en Flutter que funciona como lanzador/emulador de consolas (interfaz tipo "Playstations").
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
	- `screens/` — pantallas y UI (incluye `settings_panel.dart`, `emulator_screen.dart`, etc.)
	- `services/` — helpers y servicios como `settings_service.dart`, `audio_service.dart`, `emulator_manager.dart`, `controller_light_service.dart` (si aplica)
	- `widgets/`, `ui/` — componentes UI reutilizables y temas
- `assets/` — iconos, imágenes, sonidos
- `installer/` — script PowerShell, plantilla Inno Setup `.iss` y output del instalador
- `build/` — artefactos de build

## Notas técnicas y recomendaciones

- Deprecaciones: el proyecto usa APIs que fueron marcadas como deprecated por Flutter (por ejemplo `RawKeyboardListener` y `RawKeyEvent`). Recomiendo migrar a `KeyboardListener` y `KeyEvent` para mantener compatibilidad futura.
- Concurrencia/async: hay advertencias `use_build_context_synchronously` en varios lugares; revisar `if (mounted)` y evitar acceder a `BuildContext` después de await donde no sea seguro.
- Tests: agregar pruebas unitarias (ej.: `test/widget_test.dart` está presente como ejemplo). Añadir pruebas para `SettingsService` y lógica crítica.
- Localización: si la app se destina a múltiples idiomas, centralizar cadenas de texto y usar `flutter_localizations`.

## Cómo contribuir

- Abre un issue para reportar bugs o solicitar mejoras.
- Para cambios grandes (migraciones de API, refactorizaciones), crea una branch con nombre descriptivo y abre un pull request con la descripción de los cambios y pasos para probar.

## Créditos y licencia

Este repositorio contiene trabajo personalizado. Incluye recursos de terceros si se usan (icons, imágenes) — revisa sus licencias.

Si deseas que incluya un archivo `LICENSE` o especifique una licencia concreta (MIT, Apache-2.0, etc.), dímelo y lo añado.

---

Si quieres, puedo además:
- Generar un README específico en `installer/README.md` con instrucciones paso a paso para crear el instalador y requisitos (Inno Setup, ImageMagick, signtool).
- Ejecutar `flutter build windows --release` aquí para comprobar que la build completa funciona (ten en cuenta que tardará varios minutos).

¿Qué prefieres que haga a continuación?
