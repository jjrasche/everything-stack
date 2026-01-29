# Smoke Test History

Tracks smoke test runs (with real APIs) to analyze determinism and failure patterns.

## Directory Structure

```
smoke_test_history/
├── README.md (this file)
├── YYYY-MM-DD_HH-MM-SS.json (individual run results)
└── summary.csv (aggregated results for analysis)
```

## Running Smoke Tests with Logging

```bash
# Run smoke tests and save results
flutter test integration_test/shared/logic_test_runner.dart --dart-define=SMOKE_TEST=true -d windows --reporter json > integration_test/smoke_test_history/$(date +%Y-%m-%d_%H-%M-%S).json 2>&1
```

## File Format

Each JSON file contains:
- Timestamp
- Platform
- Test results (pass/fail)
- Real LLM responses
- Execution times

## Analysis

Use `summary.csv` to track:
- Test determinism (% of runs that pass)
- Common failure points
- LLM response variability
- Performance trends
