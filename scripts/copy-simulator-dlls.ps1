$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$destination = Join-Path $taskRoot 'simulator/bin'
# Keep the GCC runtime from the same distribution as RtAudio and RtMidi.
# GNAT's DLLs have the same names but are not compatible with this bundle.
$libraries = @(
    '.tools/csfml/CSFML/bin/csfml-graphics-2.dll',
    '.tools/csfml/CSFML/bin/csfml-window-2.dll',
    '.tools/msys64/ucrt64/bin/librtaudio-7.dll',
    '.tools/msys64/ucrt64/bin/librtmidi-7.dll',
    '.tools/msys64/ucrt64/bin/libgcc_s_seh-1.dll',
    '.tools/msys64/ucrt64/bin/libstdc++-6.dll',
    '.tools/msys64/ucrt64/bin/libwinpthread-1.dll'
)
foreach ($library in $libraries) {
    if (-not (Test-Path -LiteralPath (Join-Path $taskRoot $library))) {
        throw "Missing $library. Run scripts/setup-windows.ps1 first."
    }
}
New-Item -ItemType Directory -Force $destination | Out-Null
foreach ($library in $libraries) {
    Copy-Item -LiteralPath (Join-Path $taskRoot $library) -Destination $destination -Force
}
Write-Output "Bundled $($libraries.Count) runtime DLLs in simulator/bin."
