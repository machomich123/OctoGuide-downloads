@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Tortoise Crew - one-time update
echo Tortoise Crew - one-time update to the self-updating app
echo.
if not exist "%LOCALAPPDATA%\TortoiseCrewNext\app\src\main.mjs" (
  echo The old launcher has not installed Tortoise Crew Next yet.
  echo Open Tortoise Crew Launcher and install the offered EXE update first.
  pause
  exit /b 1
)
where node.exe >nul 2>nul
if errorlevel 1 (
  echo Official Node.js runtime is missing. Install/update the legacy launcher first.
  pause
  exit /b 1
)
set "INSTALLER=%TEMP%\tortoise-crew-install-once-%RANDOM%%RANDOM%.mjs"
powershell.exe -NoProfile -NonInteractive -Command "$ErrorActionPreference='Stop'; $url='https://raw.githubusercontent.com/machomich123/OctoGuide-downloads/main/tortoise-crew/next/install-once.mjs?fresh='+[guid]::NewGuid().ToString('N'); Invoke-WebRequest -UseBasicParsing -TimeoutSec 25 -Uri $url -OutFile $env:INSTALLER"
if errorlevel 1 (
  echo Unable to download the launcher installer from official GitHub.
  pause
  exit /b 1
)
node.exe "%INSTALLER%"
set "RESULT=%ERRORLEVEL%"
del /q "%INSTALLER%" >nul 2>nul
if not "%RESULT%"=="0" (
  echo Update could not finish. The previous app should still be available.
  pause
  exit /b %RESULT%
)
echo.
echo Updated successfully. Future updates arrive through the normal desktop shortcut.
pause
exit /b 0
