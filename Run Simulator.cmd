@echo off
setlocal
cd /d "%~dp0simulator" || exit /b 1
if not exist "bin\wnm-pgb1-simulator.exe" (
    echo Simulator is missing. Build it using scripts\build.ps1 first.
    pause
    exit /b 1
)
if not exist "..\artifacts" mkdir "..\artifacts"
"bin\wnm-pgb1-simulator.exe" "--rom=%~dp0artifacts\pgb1-cfw-simulator.rom" "--rom-desc=share/wnm_pgb1_simulator/rom_desc.toml"
if errorlevel 1 (
    echo Simulator exited with an error. See the messages above.
    pause
    exit /b 1
)
