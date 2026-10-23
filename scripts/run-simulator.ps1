param([string]$Rom = '')
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path -LiteralPath "$taskRoot/simulator/bin/librtaudio-7.dll")) {
    & (Join-Path $PSScriptRoot 'copy-simulator-dlls.ps1')
}
New-Item -ItemType Directory -Force (Join-Path $taskRoot 'artifacts') | Out-Null
Push-Location (Join-Path $taskRoot 'simulator')
try {
    if (-not $Rom) { $Rom = Join-Path $taskRoot 'artifacts/pgb1-cfw-simulator.rom' }
    & './bin/wnm-pgb1-simulator.exe' "--rom=$Rom" `
        '--rom-desc=share/wnm_pgb1_simulator/rom_desc.toml'
    if ($LASTEXITCODE -ne 0) { throw 'Simulator exited with an error.' }
} finally { Pop-Location }
