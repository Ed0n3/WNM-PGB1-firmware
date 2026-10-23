param(
    [ValidateSet('device', 'simulator', 'tests', 'all')]
    [string]$Target = 'all',
    [string]$Python = 'python',
    [switch]$RunTests
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$alire = Join-Path $taskRoot '.tools/alire/bin/alr.exe'
$settings = Join-Path $taskRoot '.tools/alire-settings'
if (-not (Test-Path -LiteralPath $alire)) {
    throw 'Run scripts/setup-windows.ps1 first.'
}
New-Item -ItemType Directory -Force (Join-Path $taskRoot 'artifacts') | Out-Null
$alireArgs = @('-s', $settings, '-n')
function Invoke-Alire {
    param([string[]]$Arguments)
    & $alire @alireArgs @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Alire failed: $Arguments" }
}

Push-Location $taskRoot
try {
    if ($Target -in @('device', 'all')) {
        $log = Join-Path $taskRoot '.tools/device-link-verbose.log'
        & $alire @alireArgs -f -C device build --release -- -v *> $log
        if ($LASTEXITCODE -ne 0) {
            $failure = Get-Content -LiteralPath $log -Raw
            if ($failure -notmatch "cannot execute.*collect2.exe") {
                Get-Content -LiteralPath $log -Tail 50
                throw 'Firmware compilation failed.'
            }
            # Use the compiler's own link plan if Windows rejects collect2.
            & $Python (Join-Path $PSScriptRoot 'link_device.py')
            if ($LASTEXITCODE -ne 0) { throw 'Direct GNU ld link failed.' }
        }
        $compiler = Get-ChildItem '.tools/toolchains/gnat_arm_elf_14.2.1_*/bin/arm-eabi-objcopy.exe' |
            Select-Object -First 1
        if (-not $compiler) { throw 'ARM GNAT 14.2.1 was not found.' }
        $elf = Get-ChildItem 'device/bin/WNM-*-release.elf' |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        Copy-Item -LiteralPath $elf.FullName -Destination 'artifacts/pgb1-cfw.elf' -Force
        & $Python (Join-Path $PSScriptRoot 'elf_to_uf2.py') $elf.FullName `
            (Join-Path $taskRoot 'artifacts/pgb1-cfw.uf2') --objcopy $compiler.FullName
        if ($LASTEXITCODE -ne 0) { throw 'UF2 conversion failed.' }
    }
    if ($Target -in @('simulator', 'tests', 'all')) {
        Invoke-Alire @('-f', '-C', 'simulator', 'build', '--stop-after=generation')
        $native = Get-ChildItem '.tools/toolchains/gnat_native_16.1.0_*' -Directory |
            Select-Object -First 1
        $gpr = Get-ChildItem '.tools/toolchains/gprbuild_26.0.1_*' -Directory |
            Select-Object -First 1
        if (-not $native -or -not $gpr) { throw 'Native GNAT/GPRbuild is missing.' }
        $env:Path = "$($native.FullName)/bin;$taskRoot/.tools/csfml/CSFML/bin;" +
            "$taskRoot/.tools/msys64/ucrt64/bin;" + $env:Path
        $env:LIBRARY_PATH = "$taskRoot/.tools/csfml/CSFML/lib/gcc;" +
            "$taskRoot/.tools/msys64/ucrt64/lib"
        $env:C_INCLUDE_PATH = "$taskRoot/.tools/msys64/ucrt64/include"
        & "$($gpr.FullName)/bin/gprconfig.exe" --batch --config=Ada --config=C `
            --target=x86_64-w64-mingw32 -o "$taskRoot/.tools/native.cgpr"
        if ($LASTEXITCODE -ne 0) { throw 'Native compiler configuration failed.' }
        if ($Target -in @('simulator', 'all')) {
            Invoke-Alire @('-C', 'simulator', 'exec', '--', 'gprbuild',
                "--config=$taskRoot/.tools/native.cgpr", '-j0', '-P', 'wnm_pgb1_simulator.gpr')
        }
        if ($Target -in @('tests', 'all')) {
            Invoke-Alire @('-C', 'simulator', 'exec', '--', 'gprbuild',
                "--config=$taskRoot/.tools/native.cgpr", '-j0', '-P', 'cfw_tests.gpr')
        }
        & (Join-Path $PSScriptRoot 'copy-simulator-dlls.ps1')
        if ($RunTests -and $Target -in @('tests', 'all')) {
            Push-Location simulator
            try {
                & './bin/cfw-tests.exe' 2>&1 |
                    Tee-Object -FilePath (Join-Path $taskRoot '.tools/test-run.log')
                if ($LASTEXITCODE -ne 0) { throw 'Regression tests failed.' }
            } finally { Pop-Location }
        }
    }
} finally { Pop-Location }
