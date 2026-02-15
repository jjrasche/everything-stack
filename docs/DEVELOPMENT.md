# Development Guide

## Build and Run

### Local Development
```bash
cp .env.example .env              # Create env from template
# Edit .env with API keys: GROQ_API_KEY, DEEPGRAM_API_KEY, JINA_API_KEY

flutter run -d windows            # Windows
flutter run -d macos              # macOS
flutter run -d ios                # iOS simulator
flutter run -d android            # Android emulator
flutter run -d chrome             # Web
```

`.env` loads in debug mode only via `flutter_dotenv`. Fallback chain: `.env` -> `.env.example` -> compile-time env vars.

### Building for Deployment
```bash
flutter build apk \
  --dart-define=GROQ_API_KEY=${{ secrets.GROQ_API_KEY }} \
  --dart-define=DEEPGRAM_API_KEY=${{ secrets.DEEPGRAM_API_KEY }}
```

Same pattern for `ipa`, `macos`, `windows`, `web`. Keys are baked into the binary at compile time.

### Environment Variables (Priority Order)

**Debug mode:** `.env` file -> `.env.example` fallback -> `--dart-define` -> OS env vars
**Release mode:** `--dart-define` only (no file-based loading)
**CI/CD:** GitHub secrets passed as `--dart-define=GROQ_API_KEY=${{ secrets.GROQ_API_KEY }}`

---

## Rust Code Changes (flutter_rust_bridge)

Rust code rebuilds automatically via Flutter's native asset build hook (`hook/build.dart`).

- **Build hook:** `hook/build.dart` uses `native_toolchain_rust`
- **Toolchain:** `rust/rust-toolchain.toml` specifies Rust 1.83.0 + all platform targets
- **FFI bindings:** `lib/bridge/frb_generated.dart` (auto-generated, do not edit)
- **TLS:** Uses rustls (pure Rust) instead of native-tls for cross-platform support

### Platform Targets
- Android: 4 ABIs (aarch64, armv7, i686, x86_64)
- iOS: 3 targets (aarch64 device, aarch64-sim, x86_64-sim)
- macOS: 2 targets (aarch64, x86_64)
- Windows: x86_64-msvc
- Linux: x86_64-gnu
- Web: WASM (separate compilation path)

### When to Rebuild
- **Hot reload (`r`):** Dart code changes only
- **Hot restart (`R`):** Dart + Rust changes not requiring recompilation
- **Full rebuild:** Rust code changes in `rust/src/`

---

## Debug Infrastructure

HTTP debug server on `localhost:9999` for autonomous debugging without screenshots.

### Endpoints
```bash
curl http://localhost:9999/state                # Full app state
curl http://localhost:9999/action/listActions   # Available actions
curl http://localhost:9999/action/invoke?target=chunking.getStats
curl http://localhost:9999/search?q=hello&limit=5
curl http://localhost:9999/entity/{uuid}
curl http://localhost:9999/screenshot
curl "http://localhost:9999/action/analyzeScreenshot"  # VLM analysis
```

### File Layout
```
lib/core/debug/
  debug.dart                 # Barrel export
  debug_introspectable.dart  # Mixin for components
  debug_registry.dart        # Central registry

lib/services/debug/
  debug_server.dart          # HTTP transport
  debug_bootstrap.dart       # Wires everything
  screenshot_service.dart    # UI capture
```

### Adding Debug to a Component
```dart
class MyService with DebugIntrospectable {
  @override
  String get debugName => 'myservice';

  @override
  Map<String, dynamic> getDebugState() => {'someMetric': value};

  @override
  Map<String, DebugAction> getDebugActions() => {
    'doThing': DebugAction(
      description: 'Does something useful',
      mutates: true,
      handler: (params) async => {'result': 'done'},
    ),
  };
}

// In debug_bootstrap.dart:
registry.register(getIt<MyService>());
```

---

## Cross-Platform Dependency Management

Every package in `pubspec.yaml` must support all 6 platforms.

### Before Adding Any Package
1. Check pub.dev platform badges manually
2. Run `dart run pubspec_checker all -s -l` (can have false positives)

### Platform Detection System
Implementers declare supported platforms via `supportedPlatforms` property:
```dart
class FlutterTtsImplementer implements TTSImplementer {
  @override
  Set<String> get supportedPlatforms => {'android', 'ios', 'macos', 'windows', 'web'};
}
```

Services auto-select compatible implementers at bootstrap.

### If a Package is Missing Platform Support
1. Replace with a fully-supported alternative
2. Add fallback implementer with platform-specific registration
3. Last resort: document the limitation in ARCHITECTURE.md

---

## Template Usage

To initialize this template for a new project:

1. **Delete example code:** Remove `lib/example/`, `test/scenarios/example_scenarios.dart`
2. **Update project identity:** `pubspec.yaml` (name, description, version), replace README.md
3. **Preserve infrastructure:** Keep `lib/core/`, `lib/patterns/`, `lib/services/`, `test/harness/`
4. **Create domain structure:** Add entities to `lib/domain/`, scenarios to `test/scenarios/`

## Distribution Model

**Current:** Template repository (clone and fork). Maintain as fork to pull upstream infrastructure updates.

**Future:** Extract stable infrastructure to a package when core stabilizes and multiple apps benefit from shared updates.
