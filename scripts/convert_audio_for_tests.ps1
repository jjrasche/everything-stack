# Convert audio files to test format (16kHz mono WAV)
# Usage: .\scripts\convert_audio_for_tests.ps1

param(
    [string]$SourceDir = "C:\Users\rasche_j\OneDrive - SET Inc\Documents\Sound Recordings",
    [string]$OutputDir = "test_fixtures/audio"
)

# Create output directory if it doesn't exist
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# Input/output file mapping
$conversions = @(
    @{
        Input = Join-Path $SourceDir "set_timer_for_5_minutes_3_second_pause.m4a"
        Output = Join-Path $OutputDir "conv_turn1_set_timer.wav"
    },
    @{
        Input = Join-Path $SourceDir "actually_make_it_10_minutes_3_second_pause.m4a"
        Output = Join-Path $OutputDir "conv_turn2_change_timer.wav"
    },
    @{
        Input = Join-Path $SourceDir "cancel_the_timer.m4a"
        Output = Join-Path $OutputDir "conv_turn3_cancel_timer.wav"
    }
)

# Check ffmpeg is available
try {
    $null = ffmpeg -version 2>&1
} catch {
    Write-Host "[ERROR] ffmpeg not found. Install from https://ffmpeg.org/" -ForegroundColor Red
    exit 1
}

# Convert each file
foreach ($conv in $conversions) {
    if (!(Test-Path $conv.Input)) {
        Write-Host "[MISSING] Source file not found: $($conv.Input)" -ForegroundColor Red
        continue
    }

    Write-Host "Converting $(Split-Path $conv.Input -Leaf) -> $(Split-Path $conv.Output -Leaf)"

    # ffmpeg: convert to 16kHz mono PCM WAV
    ffmpeg -i $conv.Input -ar 16000 -ac 1 -y $conv.Output 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        $size = (Get-Item $conv.Output).Length / 1KB
        Write-Host "  [OK] Created ($([math]::Round($size, 1)) KB)" -ForegroundColor Green
    } else {
        Write-Host "  [FAILED] Conversion failed" -ForegroundColor Red
    }
}

Write-Host "`nAudio files ready in $OutputDir"
Write-Host "Run tests with: flutter test integration_test/conversational_flow_test.dart"
