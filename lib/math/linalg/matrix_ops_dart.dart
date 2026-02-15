/// Pure Dart implementation of matrix operations.
///
/// This implementation uses standard Dart code with no native dependencies.
/// Suitable for web platform and as fallback for other platforms.
///
/// Performance: O(n³) for Cholesky on n×n matrix.
/// Expected: ~100ms for 100×100 matrix on modern hardware.
library;

import 'dart:math';
import 'matrix.dart';
import 'matrix_ops.dart';

/// Pure Dart implementation of MatrixOps
class MatrixOpsDart implements MatrixOps {
  @override
  Matrix cholesky(Matrix A, {double epsilon = 1e-6}) {
    int n = A.length;

    if (n == 0) {
      throw MatrixOperationException('Matrix is empty');
    }
    for (int i = 0; i < n; i++) {
      if (A[i].length != n) {
        throw MatrixOperationException('Matrix must be square');
      }
    }

    var L = List.generate(n, (_) => List<double>.filled(n, 0.0));

    // Cholesky-Banachiewicz algorithm
    for (int i = 0; i < n; i++) {
      for (int j = 0; j <= i; j++) {
        double sum = 0.0;

        // Sum over k < j
        for (int k = 0; k < j; k++) {
          sum += L[i][k] * L[j][k];
        }

        if (i == j) {
          // Diagonal element
          double value = A[i][i] - sum;

          if (i == j) {
            value += epsilon;
          }

          if (value <= 0) {
            // Matrix not positive definite
            throw MatrixNotPositiveDefiniteException(
              'Diagonal element $i is non-positive: $value. '
              'Matrix is not positive definite. Try increasing epsilon.',
            );
          }
          L[i][i] = sqrt(value);
        } else {
          // Off-diagonal element
          if (L[j][j] == 0.0) {
            throw MatrixNotPositiveDefiniteException(
              'Division by zero at position ($i, $j). Matrix is singular.',
            );
          }
          L[i][j] = (A[i][j] - sum) / L[j][j];
        }
      }
    }

    return L;
  }

  @override
  Matrix multiply(Matrix A, Matrix B) {
    if (A.isEmpty || B.isEmpty) {
      throw MatrixOperationException('Cannot multiply empty matrices');
    }

    int m = A.length;
    int n = A[0].length;
    int p = B[0].length;

    if (B.length != n) {
      throw MatrixOperationException(
        'Matrix dimensions incompatible for multiplication: '
        '($m×$n) × (${B.length}×$p)',
      );
    }

    var C = zeros(m, p);
    for (int i = 0; i < m; i++) {
      for (int j = 0; j < p; j++) {
        double sum = 0.0;
        for (int k = 0; k < n; k++) {
          sum += A[i][k] * B[k][j];
        }
        C[i][j] = sum;
      }
    }

    return C;
  }

  @override
  Vector forwardSubstitution(Matrix L, Vector b) {
    int n = L.length;

    if (b.length != n) {
      throw MatrixOperationException(
        'Vector length (${b.length}) must match matrix size ($n)',
      );
    }

    var x = List<double>.filled(n, 0.0);

    for (int i = 0; i < n; i++) {
      double sum = 0.0;
      for (int j = 0; j < i; j++) {
        sum += L[i][j] * x[j];
      }

      if (L[i][i] == 0.0) {
        throw MatrixOperationException(
          'Zero diagonal element at position $i. Matrix is singular.',
        );
      }

      x[i] = (b[i] - sum) / L[i][i];
    }

    return x;
  }

  @override
  Vector backwardSubstitution(Matrix U, Vector b) {
    int n = U.length;

    if (b.length != n) {
      throw MatrixOperationException(
        'Vector length (${b.length}) must match matrix size ($n)',
      );
    }

    var x = List<double>.filled(n, 0.0);

    for (int i = n - 1; i >= 0; i--) {
      double sum = 0.0;
      for (int j = i + 1; j < n; j++) {
        sum += U[i][j] * x[j];
      }

      if (U[i][i] == 0.0) {
        throw MatrixOperationException(
          'Zero diagonal element at position $i. Matrix is singular.',
        );
      }

      x[i] = (b[i] - sum) / U[i][i];
    }

    return x;
  }
}

/// Factory function for conditional import
MatrixOps createMatrixOps() => MatrixOpsDart();
