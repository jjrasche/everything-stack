@echo off
setlocal enabledelayedexpansion

REM Add NUGET to path
set PATH=C:\Tools;%PATH%

REM Verify NUGET is available
where nuget.exe
if errorlevel 1 (
    echo ERROR: nuget.exe not found in PATH
    exit /b 1
)

echo NUGET found at:
nuget.exe
echo.
echo Starting audio pipeline integration test...
echo.

cd /d C:\Users\rasche_j\Documents\workspace\everything-stack
flutter test integration_test/audio_pipeline_test.dart -d windows

endlocal
pause
