/// FFI-based matrix operations using BLAS libraries.
///
/// **CURRENT STATUS: Using pure Dart implementation**
///
/// This file exists to support future FFI optimization when needed.
/// The conditional import pattern is ready - we can drop in FFI later.
///
/// **Why pure Dart for now:**
/// - GP training performance is sufficient (~8-14ms for 100×100 Cholesky)
/// - Training happens in background, not hot path
/// - FFI adds complexity (native library bundling, platform testing)
/// - Can optimize later when robotics/vision workloads demand it
///
/// **Future FFI implementation would use:**
/// - iOS/macOS: Apple Accelerate framework (system library)
/// - Android: OpenBLAS (bundled, all 4 ABIs)
/// - Windows/Linux: OpenBLAS (bundled)
///
/// **Performance target with FFI:**
/// - 100×100 Cholesky: ~0.01ms (10,000x faster than pure Dart)
///
/// **To enable FFI later:**
/// 1. Bundle OpenBLAS binaries in `lib/math/linalg/native/`
/// 2. Replace `createMatrixOps()` with FFI implementation
/// 3. Run integration tests on all platforms
///
/// No changes needed elsewhere - conditional import handles the swap.
library;

import 'matrix_ops.dart';
import 'matrix_ops_dart.dart';

/// Factory function for conditional import.
///
/// Returns pure Dart implementation. Replace with FFI when needed.
MatrixOps createMatrixOps() {
  return MatrixOpsDart();
}
