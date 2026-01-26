#!/bin/bash
# Reliable Rust rebuild script for flutter_rust_bridge integration.
#
# USE THIS SCRIPT when you've modified Rust code and want to ensure
# changes are reflected in Flutter tests/app runs.
#
# Why this is needed:
# - Flutter caches native libraries (.dll/.so)
# - Cargo has incremental compilation in rust/target/
# - Sometimes timestamps don't propagate correctly
# - This script forces a proper rebuild

set -e  # Exit on any error

echo "🦀 [Rebuild Rust] Starting reliable Rust rebuild..."

# Step 1: Clean only Rust artifacts (fast, targeted)
echo "📦 [1/4] Cleaning Rust build artifacts..."
cd rust
cargo clean
cd ..

# Step 2: Rebuild Rust library
echo "🔨 [2/4] Building Rust library..."
cd rust
cargo build --release
cd ..

# Step 3: Regenerate FFI bindings (Dart side)
echo "🔗 [3/4] Regenerating FFI bindings..."
flutter_rust_bridge_codegen generate \
  --rust-input "crate::api" \
  --rust-root rust/ \
  --dart-output lib/bridge/

# Step 4: Touch Flutter's native build markers to force rebuild
echo "🔄 [4/4] Forcing Flutter to see changes..."
# Remove Flutter's cached native build outputs
rm -rf build/windows/x64/runner/Debug/*.dll 2>/dev/null || true
rm -rf build/windows/x64/runner/Release/*.dll 2>/dev/null || true
rm -rf build/macos/Build/Products/Debug/*.dylib 2>/dev/null || true
rm -rf build/linux/x64/debug/bundle/lib/*.so 2>/dev/null || true

echo "✅ [Rebuild Rust] Complete! Rust changes will be reflected in next Flutter run/test."
echo ""
echo "Next steps:"
echo "  flutter test integration_test/nerve/deepgram_integration_test.dart -d windows"
echo "  flutter run -d windows"
