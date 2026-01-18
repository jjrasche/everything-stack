/// Matrix representation and basic utilities.
///
/// Matrices are represented as List<List<double>> in row-major order.
/// This library provides type aliases and utility functions for matrix operations.
library;

/// Matrix type alias: row-major 2D array
typedef Matrix = List<List<double>>;

/// Vector type alias: 1D array
typedef Vector = List<double>;

/// Create a zero matrix of size n x m
Matrix zeros(int rows, int cols) {
  return List.generate(rows, (_) => List<double>.filled(cols, 0.0));
}

/// Create an identity matrix of size n x n
Matrix identity(int n) {
  final result = zeros(n, n);
  for (int i = 0; i < n; i++) {
    result[i][i] = 1.0;
  }
  return result;
}

/// Create a matrix from a flat list (row-major)
Matrix fromFlat(List<double> data, int rows, int cols) {
  if (data.length != rows * cols) {
    throw ArgumentError('Data length must equal rows * cols');
  }
  final result = zeros(rows, cols);
  for (int i = 0; i < rows; i++) {
    for (int j = 0; j < cols; j++) {
      result[i][j] = data[i * cols + j];
    }
  }
  return result;
}

/// Convert matrix to flat list (row-major)
List<double> toFlat(Matrix matrix) {
  final result = <double>[];
  for (final row in matrix) {
    result.addAll(row);
  }
  return result;
}

/// Get matrix dimensions as (rows, cols)
(int, int) shape(Matrix matrix) {
  if (matrix.isEmpty) return (0, 0);
  return (matrix.length, matrix[0].length);
}

/// Transpose a matrix
Matrix transpose(Matrix matrix) {
  if (matrix.isEmpty) return [];
  final (rows, cols) = shape(matrix);
  final result = zeros(cols, rows);
  for (int i = 0; i < rows; i++) {
    for (int j = 0; j < cols; j++) {
      result[j][i] = matrix[i][j];
    }
  }
  return result;
}
