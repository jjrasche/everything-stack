@echo off
REM Reliable Rust rebuild script for flutter_rust_bridge integration (Windows).
REM
REM USE THIS SCRIPT when you've modified Rust code and want to ensure
REM changes are reflected in Flutter tests/app runs.
REM
REM Why this is needed:
REM - Flutter caches native libraries (.dll)
REM - Cargo has incremental compilation in rust\target\
REM - Sometimes timestamps don't propagate correctly
REM - This script forces a proper rebuild

echo 🦀 [Rebuild Rust] Starting reliable Rust rebuild...

REM Step 1: Clean only Rust artifacts (fast, targeted)
echo 📦 [1/4] Cleaning Rust build artifacts...
cd rust
cargo clean
cd ..

REM Step 2: Rebuild Rust library
echo 🔨 [2/4] Building Rust library...
cd rust
cargo build --release
cd ..

REM Step 3: Regenerate FFI bindings (Dart side)
echo 🔗 [3/4] Regenerating FFI bindings...
flutter_rust_bridge_codegen generate --rust-input "crate::api" --rust-root rust/ --dart-output lib/bridge/

REM Step 4: Touch Flutter's native build markers to force rebuild
echo 🔄 [4/4] Forcing Flutter to see changes...
if exist build\windows\x64\runner\Debug\*.dll del /q build\windows\x64\runner\Debug\*.dll
if exist build\windows\x64\runner\Release\*.dll del /q build\windows\x64\runner\Release\*.dll

echo ✅ [Rebuild Rust] Complete! Rust changes will be reflected in next Flutter run/test.
echo.
echo Next steps:
echo   flutter test integration_test\io\deepgram_integration_test.dart -d windows
echo   flutter run -d windows
