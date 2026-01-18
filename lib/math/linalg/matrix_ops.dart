/// Matrix operations interface with platform-specific implementations.
///
/// This library provides a factory that selects the best implementation:
/// - FFI BLAS (native platforms): ~10,000x faster
/// - Pure Dart (web/fallback): Portable but slower
library;

import 'matrix.dart';
import 'matrix_ops_dart.dart';

// Conditional import for FFI implementation (native platforms only)
import 'matrix_ops_dart.dart'
    if (dart.library.io) 'matrix_ops_ffi.dart' as impl;

/// Exception thrown when matrix operations fail
class MatrixOperationException implements Exception {
  final String message;
  MatrixOperationException(this.message);

  @override
  String toString() => 'MatrixOperationException: $message';
}

/// Exception for non-positive-definite matrices
class MatrixNotPositiveDefiniteException extends MatrixOperationException {
  MatrixNotPositiveDefiniteException(String message) : super(message);
}

/// Interface for matrix operations
abstract class MatrixOps {
  /// Cholesky decomposition: A = L * L^T
  ///
  /// Returns lower triangular matrix L such that A = L * L^T.
  /// Throws [MatrixNotPositiveDefiniteException] if A is not positive definite.
  ///
  /// [epsilon] adds regularization to diagonal for numerical stability.
  Matrix cholesky(Matrix A, {double epsilon = 1e-6});

  /// Matrix multiplication: C = A * B
  ///
  /// A must have dimensions (m, n), B must have (n, p).
  /// Returns C with dimensions (m, p).
  Matrix multiply(Matrix A, Matrix B);

  /// Forward substitution: solve L * x = b for x
  ///
  /// L must be lower triangular.
  Vector forwardSubstitution(Matrix L, Vector b);

  /// Backward substitution: solve U * x = b for x
  ///
  /// U must be upper triangular.
  Vector backwardSubstitution(Matrix U, Vector b);
}

/// Get the best available matrix operations implementation
MatrixOps getMatrixOps() {
  // Conditional import will select FFI on native, Dart on web
  return impl.createMatrixOps();
}
