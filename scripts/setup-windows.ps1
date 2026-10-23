$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
Push-Location $taskRoot
try {
    New-Item -ItemType Directory -Force '.tools/alire-settings' | Out-Null
    if (-not (Test-Path -LiteralPath '.tools/alire/bin/alr.exe')) {
        Invoke-WebRequest 'https://github.com/alire-project/alire/releases/download/v2.1.1/alr-2.1.1-bin-x86_64-windows.zip' `
            -OutFile '.tools/alire.zip'
        Expand-Archive -LiteralPath '.tools/alire.zip' -DestinationPath '.tools/alire' -Force
    }
    $alire = Join-Path $taskRoot '.tools/alire/bin/alr.exe'
    $settings = Join-Path $taskRoot '.tools/alire-settings'
    function Invoke-AlireSetup {
        param([string[]]$Arguments)
        & $alire -s $settings -n @Arguments
        if ($LASTEXITCODE -ne 0) { throw "Alire setup failed: $Arguments" }
    }
    Invoke-AlireSetup @('settings', '--global', '--set', 'cache.dir', "$taskRoot/.tools/cache")
    Invoke-AlireSetup @('settings', '--global', '--set', 'toolchain.dir', "$taskRoot/.tools/toolchains")
    Invoke-AlireSetup @('settings', '--global', '--set', 'msys2.install_dir', "$taskRoot/.tools/msys64")
    Invoke-AlireSetup @('settings', '--global', '--set', 'dependencies.shared', 'false')
    Invoke-AlireSetup @('settings', '--global', '--set', 'solver.timeout', '120')
    Invoke-AlireSetup @('toolchain', '--select', 'gnat_native=16.1.0', 'gprbuild=26.0.1')
    Invoke-AlireSetup @('-C', 'device', 'update')
    # The C libraries below are provided explicitly, rather than using the old
    # MINGW64 package names in Alire's external dependency index.
    Invoke-AlireSetup @('-f', '-C', 'simulator', 'update')
    Invoke-AlireSetup @('-C', 'simulator', 'toolchain', '--select', '--local',
        'gnat_native=16.1.0', 'gprbuild=26.0.1')
    $env:Path = "$taskRoot/.tools/msys64/usr/bin;" + $env:Path
    & './.tools/msys64/usr/bin/pacman.exe' -S --needed --noconfirm `
        mingw-w64-ucrt-x86_64-rtmidi mingw-w64-ucrt-x86_64-rtaudio
    if ($LASTEXITCODE -ne 0) { throw 'Native audio library installation failed.' }
    if (-not (Test-Path -LiteralPath '.tools/csfml/CSFML/bin/csfml-graphics-2.dll')) {
        Invoke-WebRequest 'https://github.com/SFML/CSFML/releases/download/2.6.1/CSFML-2.6.1-windows-64-bit.zip' `
            -OutFile '.tools/csfml.zip'
        Expand-Archive -LiteralPath '.tools/csfml.zip' -DestinationPath '.tools/csfml' -Force
    }
    Write-Output 'Tools installed. Run scripts/build.ps1 with Python 3 available.'
} finally { Pop-Location }
