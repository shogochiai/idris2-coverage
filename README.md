# idris2-coverage

Code coverage tool for Idris2 using Chez Scheme's profiler.

## Requirements

- Idris2 0.8.0+
- Chez Scheme 10.0+

## Build

```bash
idris2 --build idris2-coverage.ipkg
```

## Usage

```bash
# Generate coverage report (JSON)
idris2-cov --format json --output coverage.json myproject.ipkg

# Generate coverage report (text)
idris2-cov --format text myproject.ipkg

# Run tests with profiling and generate coverage
idris2-cov --run-tests "src/*/Tests/*_Test.idr" -o coverage.json myproject.ipkg
```

## Output Format

JSON output follows lazy-idris coverage schema:

```json
{
  "functions": [
    {
      "module": "Sample",
      "name": "add",
      "signature": "Int -> Int -> Int",
      "line_start": 5,
      "line_end": 6,
      "covered_lines": 2,
      "total_lines": 2,
      "coverage_percent": 100.0,
      "called_by_tests": ["test_add", "test_integration"]
    }
  ],
  "modules": [
    {
      "path": "src/Sample.idr",
      "functions_total": 4,
      "functions_covered": 3,
      "line_coverage_percent": 75.0
    }
  ],
  "project": {
    "total_functions": 4,
    "covered_functions": 3,
    "line_coverage_percent": 75.0,
    "branch_coverage_percent": null
  }
}
```

## How It Works

1. **Profile Collection**: Parses Chez Scheme's `profile.html` output from `--profile` builds
2. **Scheme Analysis**: Maps Scheme function names (e.g., `SampleC-45Module-add`) back to Idris modules
3. **Source Analysis**: Extracts exported functions with line ranges from `.idr` files
4. **Aggregation**: Computes `called_by_tests` by running each test individually with profiling

### Naming Convention

Idris module names are converted to Scheme format:
- `Sample` → `Sample-functionName`
- `Audit.Orchestrator` → `AuditC-45Orchestrator-functionName`

## Project Structure

```
src/
├── Main.idr                 # CLI entry point
└── Coverage/
    ├── Types.idr            # Core type definitions
    ├── Collector.idr        # profile.html and .ss parsing
    ├── SourceAnalyzer.idr   # Idris source analysis
    ├── TestRunner.idr       # Test execution with profiling
    ├── Aggregator.idr       # called_by_tests computation
    ├── Report.idr           # JSON/Text output
    └── Tests/               # Unit tests
```

## Running Tests

```bash
idris2 -o test-runner -p idris2-coverage src/Coverage/Tests.idr
./build/exec/test-runner
```

## License

MIT
