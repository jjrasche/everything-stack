/// Harmonic mean penalizes imbalance — a system that extracts
/// everything (high coverage) but mostly junk (low focus) scores
/// poorly, and vice versa.
double harmonicMean(double a, double b) {
  if (a + b == 0) return 0;
  return 2 * a * b / (a + b);
}
