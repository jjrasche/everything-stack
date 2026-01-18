/// Unit tests for matrix operations (pure Dart implementation)
import 'package:flutter_test/flutter_test.dart';
import 'package:everything_stack_template/math/linalg/matrix.dart';
import 'package:everything_stack_template/math/linalg/matrix_ops.dart';
import 'dart:math';

void main() {
  group('Matrix Utilities', () {
    test('zeros creates zero matrix', () {
      final m = zeros(3, 4);
      expect(m.length, 3);
      expect(m[0].length, 4);
      expect(m[1][2], 0.0);
    });

    test('identity creates identity matrix', () {
      final I = identity(3);
      expect(I[0][0], 1.0);
      expect(I[1][1], 1.0);
      expect(I[2][2], 1.0);
      expect(I[0][1], 0.0);
      expect(I[1][0], 0.0);
    });

    test('transpose swaps rows and columns', () {
      final A = [
        [1.0, 2.0, 3.0],
        [4.0, 5.0, 6.0],
      ];
      final At = transpose(A);
      expect(At.length, 3);
      expect(At[0].length, 2);
      expect(At[0][0], 1.0);
      expect(At[1][0], 2.0);
      expect(At[2][1], 6.0);
    });

    test('fromFlat creates matrix from flat array', () {
      final flat = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0];
      final m = fromFlat(flat, 2, 3);
      expect(m[0][0], 1.0);
      expect(m[0][2], 3.0);
      expect(m[1][1], 5.0);
    });

    test('toFlat converts matrix to flat array', () {
      final m = [
        [1.0, 2.0],
        [3.0, 4.0],
      ];
      final flat = toFlat(m);
      expect(flat, [1.0, 2.0, 3.0, 4.0]);
    });
  });

  group('MatrixOps - Cholesky Decomposition', () {
    late MatrixOps ops;

    setUp(() {
      ops = getMatrixOps();
    });

    test('cholesky 3x3 positive definite matrix', () {
      // A = [4  12  -16]
      //     [12 37  -43]
      //     [-16 -43 98]
      // L = [2  0  0]
      //     [6  1  0]
      //     [-8 5  3]
      final A = [
        [4.0, 12.0, -16.0],
        [12.0, 37.0, -43.0],
        [-16.0, -43.0, 98.0],
      ];

      final L = ops.cholesky(A, epsilon: 0.0);

      // Check L is lower triangular
      expect(L[0][1], closeTo(0.0, 1e-10));
      expect(L[0][2], closeTo(0.0, 1e-10));
      expect(L[1][2], closeTo(0.0, 1e-10));

      // Check L * L^T = A
      final Lt = transpose(L);
      final reconstructed = ops.multiply(L, Lt);

      for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
          expect(
            reconstructed[i][j],
            closeTo(A[i][j], 1e-10),
            reason: 'Element [$i][$j] mismatch',
          );
        }
      }
    });

    test('cholesky identity matrix', () {
      final I = identity(5);
      final L = ops.cholesky(I, epsilon: 0.0);

      // Cholesky of identity should be identity
      for (int i = 0; i < 5; i++) {
        expect(L[i][i], closeTo(1.0, 1e-10));
        for (int j = 0; j < i; j++) {
          expect(L[i][j], closeTo(0.0, 1e-10));
        }
      }
    });

    test('cholesky 10x10 random positive definite matrix', () {
      // Create positive definite matrix: A = B * B^T
      final random = Random(42);
      final B = List.generate(
        10,
        (i) => List.generate(10, (j) => random.nextDouble() * 2 - 1),
      );
      final Bt = transpose(B);
      final A = ops.multiply(B, Bt);

      // Add small diagonal for numerical stability
      for (int i = 0; i < 10; i++) {
        A[i][i] += 0.1;
      }

      final L = ops.cholesky(A);

      // Verify L * L^T ≈ A
      final Lt = transpose(L);
      final reconstructed = ops.multiply(L, Lt);

      for (int i = 0; i < 10; i++) {
        for (int j = 0; j < 10; j++) {
          expect(
            reconstructed[i][j],
            closeTo(A[i][j], 1e-5), // Relaxed tolerance for accumulated floating point errors
            reason: 'Element [$i][$j] mismatch',
          );
        }
      }
    });

    test('cholesky 100x100 performance benchmark', () {
      // Create 100x100 positive definite matrix
      final random = Random(123);
      final B = List.generate(
        100,
        (i) => List.generate(100, (j) => random.nextDouble() * 2 - 1),
      );
      final Bt = transpose(B);
      final A = ops.multiply(B, Bt);

      // Add diagonal for stability
      for (int i = 0; i < 100; i++) {
        A[i][i] += 1.0;
      }

      final stopwatch = Stopwatch()..start();
      final L = ops.cholesky(A);
      stopwatch.stop();

      print('Pure Dart Cholesky 100x100: ${stopwatch.elapsedMilliseconds}ms');

      // Verify result (spot check, full check too expensive)
      final Lt = transpose(L);
      final C = ops.multiply(L, Lt);

      // Check corners and diagonal
      expect(C[0][0], closeTo(A[0][0], 1e-6));
      expect(C[50][50], closeTo(A[50][50], 1e-6));
      expect(C[99][99], closeTo(A[99][99], 1e-6));

      // Expect ~100ms on modern hardware (pure Dart)
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });

    test('cholesky throws on non-positive-definite matrix', () {
      // Singular matrix (not positive definite)
      final A = [
        [1.0, 2.0],
        [2.0, 4.0], // Row 2 = 2 * Row 1 (rank deficient)
      ];

      expect(
        () => ops.cholesky(A, epsilon: 0.0),
        throwsA(isA<MatrixNotPositiveDefiniteException>()),
      );
    });

    test('cholesky with epsilon regularization', () {
      // Nearly singular matrix
      final A = [
        [1.0, 0.999],
        [0.999, 1.0],
      ];

      // Should succeed with regularization
      final L = ops.cholesky(A, epsilon: 1e-3);
      expect(L.length, 2);

      // Verify L is lower triangular
      expect(L[0][1], 0.0);
    });
  });

  group('MatrixOps - Matrix Multiplication', () {
    late MatrixOps ops;

    setUp(() {
      ops = getMatrixOps();
    });

    test('multiply 2x3 by 3x2', () {
      final A = [
        [1.0, 2.0, 3.0],
        [4.0, 5.0, 6.0],
      ];
      final B = [
        [7.0, 8.0],
        [9.0, 10.0],
        [11.0, 12.0],
      ];

      final C = ops.multiply(A, B);

      expect(C.length, 2);
      expect(C[0].length, 2);
      expect(C[0][0], 1 * 7 + 2 * 9 + 3 * 11); // 58
      expect(C[0][1], 1 * 8 + 2 * 10 + 3 * 12); // 64
      expect(C[1][0], 4 * 7 + 5 * 9 + 6 * 11); // 139
      expect(C[1][1], 4 * 8 + 5 * 10 + 6 * 12); // 154
    });

    test('multiply identity matrix', () {
      final A = [
        [1.0, 2.0],
        [3.0, 4.0],
      ];
      final I = identity(2);

      final C = ops.multiply(A, I);
      expect(C[0][0], 1.0);
      expect(C[0][1], 2.0);
      expect(C[1][0], 3.0);
      expect(C[1][1], 4.0);
    });

    test('multiply throws on dimension mismatch', () {
      final A = [
        [1.0, 2.0],
      ];
      final B = [
        [3.0],
        [4.0],
        [5.0],
      ];

      expect(
        () => ops.multiply(A, B),
        throwsA(isA<MatrixOperationException>()),
      );
    });
  });

  group('MatrixOps - Triangular Solvers', () {
    late MatrixOps ops;

    setUp(() {
      ops = getMatrixOps();
    });

    test('forward substitution solves L*x=b', () {
      // L = [2  0  0]
      //     [4  3  0]
      //     [6  5  1]
      // For x = [1, 2, 3], b = [2, 10, 19]
      final L = [
        [2.0, 0.0, 0.0],
        [4.0, 3.0, 0.0],
        [6.0, 5.0, 1.0],
      ];
      final b = [2.0, 10.0, 19.0];

      final x = ops.forwardSubstitution(L, b);

      // x should be [1, 2, 3]
      expect(x[0], closeTo(1.0, 1e-10));
      expect(x[1], closeTo(2.0, 1e-10));
      expect(x[2], closeTo(3.0, 1e-10));

      // Verify L*x = b
      for (int i = 0; i < 3; i++) {
        double sum = 0.0;
        for (int j = 0; j <= i; j++) {
          sum += L[i][j] * x[j];
        }
        expect(sum, closeTo(b[i], 1e-10));
      }
    });

    test('backward substitution solves U*x=b', () {
      // U = [5  2  4]
      //     [0  3  1]
      //     [0  0  2]
      // For x = [1, 2, 3], b = [21, 9, 6]
      final U = [
        [5.0, 2.0, 4.0],
        [0.0, 3.0, 1.0],
        [0.0, 0.0, 2.0],
      ];
      final b = [21.0, 9.0, 6.0];

      final x = ops.backwardSubstitution(U, b);

      // x should be [1, 2, 3]
      expect(x[0], closeTo(1.0, 1e-10));
      expect(x[1], closeTo(2.0, 1e-10));
      expect(x[2], closeTo(3.0, 1e-10));

      // Verify U*x = b
      for (int i = 0; i < 3; i++) {
        double sum = 0.0;
        for (int j = i; j < 3; j++) {
          sum += U[i][j] * x[j];
        }
        expect(sum, closeTo(b[i], 1e-10));
      }
    });

    test('solvers throw on singular matrix', () {
      final L = [
        [1.0, 0.0],
        [2.0, 0.0], // Zero diagonal
      ];
      final b = [1.0, 2.0];

      expect(
        () => ops.forwardSubstitution(L, b),
        throwsA(isA<MatrixOperationException>()),
      );
    });
  });
}
