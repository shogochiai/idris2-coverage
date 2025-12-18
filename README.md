# idris2-coverage

**Pragmatic coverage library** for Idris2. Uses `--dumpcases` output to measure canonical case coverage with type-awareness.

---

## 🙏 Help Keep This Fresh

> **Your codebase keeps this project accurate.**

The exclusion patterns are **Idris2 version-dependent**. When you see unexpected stdlib/compiler functions in your report, please help us fix it:

```bash
# If you see leaks, just run:
idris2-cov --report-leak /path/to/your/project
```

This one command will:
1. Show potential leaks + **LLM prompt** to help you verify
2. Ask: existing clone location or where to clone?
3. Fork & clone via `gh` CLI (if needed)
4. Add patterns to `exclusions/<version>.txt`
5. Create a PR automatically

**Not sure what's a leak?** The script generates a prompt for Claude/ChatGPT to categorize each function. Press `c` to copy it.

**That's it. Different codebases × different Idris2 versions = better coverage for everyone.**

### Quick Start to Contributing

```bash
# 1. Install (if you haven't)
pack install idris2-coverage

# 2. Run on your project
idris2-cov --json --top 100 .

# 3. See something wrong? (stdlib functions in targets?)
#    Run the reporter - it handles everything:
idris2-cov --report-leak .
```

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#idris2-version-tracking-contributor-guide) for details.

---

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

### Denominator Exclusions (Static Analysis)

The **denominator** is calculated from `--dumpcases` output with these exclusions:

| Exclusion | Pattern | Reason |
|-----------|---------|--------|
| **NoClauses** | `CRASH "No clauses in..."` | Void/absurd - mathematically unreachable |
| **OptimizerNat** | `CRASH "Nat case not covered"` | Compiler optimization artifact |
| **Standard Library** | `Prelude.*`, `Data.*`, etc. | Not user code |
| **Compiler Generated** | `{csegen:*}`, `case block in...` | Internal compiler functions |

### Numerator Attribution (Runtime Hits)

The **numerator** uses Chez Scheme profiler data (`.ss.html`) with deterministic name matching:

1. **Idris → Scheme name mangling**: `Module.Func.==` → `ModuleC-45Func-C-61C-61`
2. **Exact/suffix matching**: Prevents mis-attribution (no `isInfixOf`)
3. **Per-function granularity**: Each function gets its actual hit count

Functions that don't match are safely excluded (stdlib, builtins, data constructors).

## Requirements

- Idris2 0.8.0+

## License

MIT
