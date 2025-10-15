# Script para automatizar build y creación del instalador
# Ejecutar PowerShell como administrador si el build o el instalador lo requiere

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
# Ajustar al root del repo si se ejecuta desde installer
$root = Resolve-Path "$projectRoot\.." | Select-Object -ExpandProperty Path

$sourceIcon = Join-Path $root 'assets\icons\emuchull.ico'
$destIcon = Join-Path $root 'windows\runner\resources\app_icon.ico'

Write-Host "Copiando icono desde $sourceIcon a $destIcon"
Copy-Item -Path $sourceIcon -Destination $destIcon -Force

Write-Host "Construyendo la app Windows (flutter build windows)"
# Cambia esto si necesitas ejecutar con un flutter específico
Push-Location $root
flutter build windows --release
if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter build windows falló con código $LASTEXITCODE"
    Pop-Location
    exit $LASTEXITCODE
}

Pop-Location

# Opciones de firma (opcional)
# Proporciona ruta al PFX y contraseña si deseas firmar el instalador
param(
    [string]$PfxPath = $null,
    [string]$PfxPassword = $null
)

# Compilar instalador con Inno Setup
$iss = Join-Path $root 'installer\playstations.iss'
$ISCC = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
if (!(Test-Path $ISCC)) {
    Write-Error "No se encontró ISCC.exe en $ISCC. Ajusta la variable `\$ISCC` a la ruta correcta de Inno Setup."
    exit 1
}

Write-Host "Compilando instalador usando ISCC: $iss"
& "$ISCC" "$iss"
if ($LASTEXITCODE -ne 0) {
    Write-Error "ISCC falló con código $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host "Instalador creado (revisa la carpeta de output indicada por el script .iss)."

# Si se indicó un PFX, intentar firmar el instalador
if ($PfxPath) {
    if (!(Test-Path $PfxPath)) {
        Write-Error "No se encontró el archivo PFX en $PfxPath"
        exit 2
    }

    $outputDir = Join-Path $root 'installer\Output'
    $installer = Get-ChildItem -Path $outputDir -Filter 'EMUCHULLSetup_*.exe' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $installer) {
        Write-Error "No se encontró el instalador en $outputDir para firmar."
        exit 3
    }

    # Buscar signtool
    $signtool = 'C:\Program Files (x86)\Windows Kits\10\bin\x64\signtool.exe'
    if (!(Test-Path $signtool)) {
        Write-Warning "signtool.exe no encontrado en la ruta por defecto: $signtool. Asegúrate de tener Windows SDK instalado o ajusta la ruta en el script."
    } else {
        Write-Host "Firmando instalador $($installer.FullName) con PFX $PfxPath"
        # Construir argumentos para signtool
        $args = @('sign', '/f', "$PfxPath")
        if ($PfxPassword) { $args += @('/p', "$PfxPassword") }
        $args += @('/tr', 'http://timestamp.digicert.com', '/td', 'sha256', '/fd', 'sha256', "$($installer.FullName)")

        & "$signtool" $args
        if ($LASTEXITCODE -ne 0) {
            Write-Error "signtool falló con código $LASTEXITCODE"
            exit $LASTEXITCODE
        }

        Write-Host "Instalador firmado correctamente: $($installer.FullName)"
    }
}