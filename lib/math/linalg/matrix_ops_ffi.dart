/// FFI-based matrix operations using BLAS libraries.
///
/// This implementation uses native BLAS libraries via FFI for ~10,000x speedup.
/// Platform-specific libraries:
/// - iOS/macOS: Apple Accelerate framework
/// - Android: OpenBLAS (all 4 ABIs)
/// - Windows: OpenBLAS DLL
/// - Linux: OpenBLAS SO
///
/// STUB: This file is a placeholder. Full FFI implementation coming in Phase 1, Step 3.
library;

import 'matrix_ops.dart';
import 'matrix_ops_dart.dart';

/// Factory function for conditional import
/// TODO(Phase 1.3): Implement FFI BLAS bindings
MatrixOps createMatrixOps() {
  // Stub: Return Dart implementation for now
  // Will be replaced with FFI implementation in Phase 1.3
  return MatrixOpsDart();
}
