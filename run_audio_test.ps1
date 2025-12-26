# PowerShell script to run audio integration test with NUGET in PATH

# Add NUGET to path
$env:Path = "C:\Tools;$($env:Path)"

# Verify NUGET is available
Write-Host "Checking for NUGET..." -ForegroundColor Cyan
$nuget = Get-Command nuget.exe -ErrorAction SilentlyContinue
if ($null -eq $nuget) {
    Write-Host "ERROR: nuget.exe not found in PATH" -ForegroundColor Red
    exit 1
}

Write-Host "✓ NUGET found at: $($nuget.Source)" -ForegroundColor Green
Write-Host ""
Write-Host "Starting audio pipeline integration test..." -ForegroundColor Cyan
Write-Host ""

Set-Location "C:\Users\rasche_j\Documents\workspace\everything-stack"
flutter test integration_test/audio_pipeline_test.dart -d windows
