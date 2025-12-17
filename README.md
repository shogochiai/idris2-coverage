# idris2-coverage

**Pragmatic coverage library** for Idris2. Uses `--dumpcases` output to measure canonical case coverage with type-awareness.

## The Problem We Solve

> Absurd / Impossible branches polluting the denominator and preventing 100%

That's it. The goal is:
1. **Exclude unreachable branches from denominator** - 100% is achievable
2. **Flag genuine gaps (UnhandledInput)** - CI can fail on partial code
3. **Ignore optimizer artifacts** - Don't count Nat->Integer translation noise

## Quick Start

```bash
# Analyze a project
idris2-cov pkgs/LazyCore

# JSON output with high-impact targets
idris2-cov --json --top 10 pkgs/LazyCore
```

## JSON Output Format

```json
{
  "reading_guide": "high_impact_targets: Functions with coverage issues...",
  "summary": {
    "total_functions": 1074,
    "total_canonical": 2883,
    "total_excluded": 45,
    "total_bugs": 0,
    "total_optimizer_artifacts": 12,
    "total_unknown": 0
  },
  "high_impact_targets": [
    {
      "kind": "untested_canonical",
      "funcName": "Options.Options.parseArgs",
      "moduleName": "Options",
      "branchCount": 22,
      "executedCount": 0,
      "severity": "Inf",
      "note": "Function has 22 untested branches"
    }
  ]
}
```

### Severity Calculation

`severity = branchCount / executedCount`
- `Inf` = no branches executed (highest priority)
- Lower ratio = better coverage
- Sorted descending: fix highest severity first

## CRASH Classification (dunham's classification)

| CRASH Message | Classification | Action |
|--------------|----------------|--------|
| `"No clauses in..."` | `CrashNoClauses` | **Exclude** from denominator |
| `"Unhandled input for..."` | `CrashUnhandledInput` | **Bug** - fix implementation |
| `"Nat case not covered"` | `CrashOptimizerNat` | **Ignore** - optimizer artifact |
| Other messages | `CrashUnknown` | **Never exclude** (conservative) |

## Filtering

### Compiler-Generated Functions

Functions like `{csegen:129}` are compiler-generated and filtered from `high_impact_targets`.
They remain in `total_canonical` but are not actionable targets.

See [docs/compiler-generated-functions.md](docs/compiler-generated-functions.md) for details.

## CLI Options

```
idris2-cov [options] [<dir-or-ipkg>]

OPTIONS:
  -h, --help        Show help
  -v, --version     Show version
  --json            JSON output with high_impact_targets
  --top N           Number of targets to show (default: 10)
  --uncovered       Only show functions with bugs/unknown CRASHes
```

## API Usage

```idris
import Coverage.SemanticCoverage

main : IO ()
main = do
  Right analysis <- analyzeProject "myproject.ipkg"
    | Left err => putStrLn $ "Error: " ++ err

  putStrLn $ "Canonical: " ++ show analysis.totalCanonical
  putStrLn $ "Excluded: " ++ show analysis.totalExcluded
  putStrLn $ "Bugs: " ++ show analysis.totalBugs
```

## Coverage Formula

```
PragmaticCoverage = executed / (canonical - impossible)
```

Where:
- `canonical` = reachable branches from `--dumpcases`
- `impossible` = `NoClauses` + `OptimizerNat`
- `executed` = branches hit at runtime (from `.ss.html` profiler)

## Requirements

- Idris2 0.8.0+

## License

MIT
