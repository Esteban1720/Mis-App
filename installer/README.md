# Build y creación del instalador EMUCHULL

Este directorio contiene el script y la configuración para crear el instalador de EMUCHULL en Windows usando Inno Setup.

Archivos importantes:
- `emuchull.iss` - Script de Inno Setup (configurado para EMUCHULL).
- `build_installer.ps1` - Script de PowerShell que automatiza:
  1. Copiar `assets/icons/emuchull.ico` a `windows/runner/resources/app_icon.ico`.
  2. Ejecutar `flutter build windows --release`.
  3. Ejecutar `ISCC.exe` para compilar el instalador.
  4. (Opcional) Firmar digitalmente el instalador con `signtool.exe` y un archivo PFX.

Uso básico (sin firma):
```powershell
cd C:\Users\DavidSax\Desktop\EmuChull\installer
# Ejecuta PowerShell como administrador si es necesario
.\build_installer.ps1
```

Firmar el instalador (opcional):
- Requisitos: tener `signtool.exe` disponible (parte del Windows SDK) y un certificado PFX válido.
- Ejecuta el script pasando la ruta al PFX y la contraseña (si aplica):
```powershell
.\build_installer.ps1 -PfxPath 'C:\ruta\a\mi_certificado.pfx' -PfxPassword 'mi_contraseña'
```

Notas:
- Si `ISCC.exe` no está en la ruta por defecto (`C:\Program Files (x86)\Inno Setup 6\ISCC.exe`), edita `build_installer.ps1` y ajusta la variable `$ISCC`.
- Si `signtool.exe` no está en la ruta por defecto, edita `build_installer.ps1` y ajusta la variable `$signtool`.
- El instalador final se genera en `installer\Output\EMUCHULLSetup_x64.exe`.

Si quieres, puedo _automáticamente_ agregar el paso de firma con un certificado que me indiques, o ajustar la configuración para firmar con un certificado de máquina (store) en lugar de PFX.
