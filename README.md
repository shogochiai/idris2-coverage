# idris2-coverage

**Pragmatic coverage library** for Idris2. Uses `--dumpcases` output to measure canonical case coverage with type-awareness.

**Self-coverage**: 170/1137 branches (14%) - measured by running `idris2-cov .`

## Pragmatic Coverage Philosophy

**The only problem this library solves:**

> Absurd / Impossible branches polluting the denominator and preventing 100%

Everything else is secondary. The goal is simple:

1. **Exclude unreachable branches from denominator** → 100% is achievable
2. **Flag genuine gaps (UnhandledInput)** → CI can fail on partial code
3. **Ignore optimizer artifacts** → Don't count Nat→Integer translation noise

This is **not** academic semantic coverage. It's practical CI coverage that:
- Trusts Idris2's `impossible` declarations
- Excludes void/absurd patterns from the denominator
- Makes 100% coverage theoretically achievable

## Status / Scope

This project uses `--dumpcases` output as a **pragmatic observation point**
to distinguish:
- type-proven unreachable cases (absurd patterns), and
- genuine coverage gaps.

**Important:**
Using `--dumpcases` is a working assumption, not a claim that it is the
ideal or intended interface for semantic coverage.

### CRASH Classification (dunham's classification)

Based on feedback from the Idris2 community (dunham), the library classifies CRASH messages into four categories:

| CRASH Message | Classification | Semantics | Action |
|--------------|----------------|-----------|--------|
| `"No clauses in..."` | `CrashNoClauses` | Void/absurd pattern | **Exclude** from denominator |
| `"Unhandled input for..."` | `CrashUnhandledInput` | Partial code bug | **Bug** - fix implementation |
| `"Nat case not covered"` | `CrashOptimizerNat` | Optimizer artifact | **Non-semantic** - warn only |
| Other messages | `CrashUnknown` | Unknown | **Never exclude** (conservative) |

**Design principle**: Unknown CRASHes are never excluded from the denominator. This conservative approach ensures genuine bugs are not accidentally hidden.


## Theoretical Foundation

This library's classification of **impossible cases** (type-excluded patterns) aligns with the concept of **absurd patterns** in dependent type theory. See [Ermondi-Kammar: Coverage Semantics for Dependent Pattern Matching (arXiv:2501.18087)](https://arxiv.org/abs/2501.18087) for the categorical semantics foundation.

**Key insight**: Idris2's `CRASH "Impossible case encountered"` in `--dumpcases` output corresponds to absurd patterns — cases that are statically unreachable due to type constraints. These are excluded from the coverage denominator because they can never execute.

## Quick Start

```idris
import Coverage.SemanticCoverage

main : IO ()
main = do
  -- Analyze project - runs idris2 --dumpcases internally
  Right analysis <- analyzeProject "myproject.ipkg"
    | Left err => putStrLn $ "Error: " ++ err

  putStrLn $ "Canonical cases: " ++ show analysis.totalCanonical
  putStrLn $ "Excluded (void etc): " ++ show analysis.totalExcluded
  putStrLn $ "Bugs (partial code): " ++ show analysis.totalBugs
  putStrLn $ "Optimizer artifacts: " ++ show analysis.totalOptimizerArtifacts
  putStrLn $ "Unknown CRASHes: " ++ show analysis.totalUnknown
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     SEMANTIC COVERAGE                                │
│  analyzeProject "myproject.ipkg"                                    │
│    → idris2 --dumpcases (internally)                                │
│    → CaseTree output → DumpcasesParser                              │
│    → Canonical vs Impossible vs NotCovered classification           │
│    → Coverage = executed_canonical / total_canonical                │
└─────────────────────────────────────────────────────────────────────┘
```

## What is Semantic Coverage?

Unlike traditional line/branch coverage, **Semantic Coverage** measures:

- **Canonical Cases**: Reachable pattern matches that can actually execute
- **Impossible Cases**: Type-excluded patterns (e.g., `Nil` for `NonEmpty`)
- **Not-Covered Cases**: Missing implementations marked as bugs

```
Coverage = executed_canonical / total_canonical
         (impossible cases excluded from denominator)
```

### CaseKind Classification

```idris
-- From Coverage.DumpcasesParser
data CrashReason
  = CrashNoClauses        -- "No clauses in..." → exclude (void/absurd)
  | CrashUnhandledInput   -- "Unhandled input for..." → bug (partial code)
  | CrashOptimizerNat     -- "Nat case not covered" → non-semantic (optimizer artifact)
  | CrashUnknown String   -- Other → never exclude (conservative)

data CaseKind
  = Canonical                    -- Reachable, should be tested
  | NonCanonical CrashReason     -- Unreachable or bug
```

### Example: --dumpcases Output

```scheme
;; idris2 --dumpcases output
Main.safeHead = [{arg:0}]
  (%case !{arg:0} [Just]
    [(%concase Just 0 [{e:1}] !{e:1})]          ;; Canonical
    Just (CRASH "Impossible case encountered")) ;; Impossible → excluded
```

Parser extracts:
- 1 canonical case (`%concase Just`)
- 1 impossible case (`CRASH "Impossible case"`)
- **Denominator = 1** (impossible excluded)

### Runtime Hits via .ss.html Profiler

When running tests with `idris2 --profile`, the Chez Scheme backend generates `.ss.html` files with expression-level execution counts. The library parses these to determine which canonical cases were actually executed at runtime.

```
┌─────────────────────────────────────────────────────────────────────┐
│  Static Analysis (--dumpcases)    │  Runtime Analysis (.ss.html)    │
├───────────────────────────────────┼─────────────────────────────────┤
│  %concase → Canonical             │  Expression hit count > 0       │
│  CRASH "Impossible" → Absurd      │  (never executed - excluded)    │
│  CRASH "not covered" → Bug        │  Expression hit count = 0 (gap) │
└───────────────────────────────────┴─────────────────────────────────┘
```

**Absurd Case Detection**:
1. **Static**: `CRASH "Impossible case encountered"` in `--dumpcases` → type system proves unreachability
2. **Runtime**: These expressions have hit count 0 in `.ss.html`, but this is *expected* — they are excluded from coverage calculation

This separation ensures that:
- Type-proven unreachable code (absurd patterns) doesn't inflate coverage requirements
- Genuinely untested code (`CRASH "case not covered"`) is flagged as a gap

## API Reference

### SemanticCoverage (High-Level)

```idris
-- Analyze project - runs idris2 --dumpcases internally
analyzeProject : String -> IO (Either String SemanticAnalysis)

-- Analyze with runtime profiler hits
analyzeProjectWithHits : String -> List String -> IO (Either String SemanticCoverage)
```

### DumpcasesParser (Low-Level)

```idris
-- Parse --dumpcases output (after running idris2 --dumpcases yourself)
parseDumpcasesFile : String -> List CompiledFunction

-- Aggregate analysis
aggregateAnalysis : List CompiledFunction -> SemanticAnalysis

-- Runtime hit mapping
matchFunctionHits : List CompiledFunction -> List (Nat, Nat, Nat) -> List FunctionHitMapping
semanticCoverageWithHits : List CompiledFunction -> List (Nat, Nat, Nat) -> SemanticCoverage
```

### Data Types

```idris
-- Compiled function from --dumpcases
record CompiledFunction where
  constructor MkCompiledFunction
  fullName       : String              -- "Module.funcName"
  moduleName     : String
  funcName       : String
  arity          : Nat
  cases          : List CompiledCase   -- With CaseKind classification
  hasDefaultCase : Bool

-- Semantic coverage per function (Pragmatic v1.0)
record FunctionSemanticCoverage where
  constructor MkFunctionSemanticCoverage
  funcName           : String
  moduleName         : String
  -- Coverage 本体
  totalCanonical     : Nat    -- Denominator
  executedCanonical  : Nat    -- Numerator (from runtime)
  coveragePercent    : Double
  -- 分母から除外（100%達成可能に）
  excludedNoClauses  : Nat    -- void/uninhabited
  excludedOptimizer  : Nat    -- Nat case artifact
  -- CI シグナル（分母に入れない）
  bugUnhandledInput  : Nat    -- partial code (should fix)
  unknownCrash       : Nat    -- conservative bucket

-- Project-level analysis (dunham's classification)
record SemanticAnalysis where
  constructor MkSemanticAnalysis
  totalFunctions         : Nat
  totalCanonical         : Nat
  totalExcluded          : Nat    -- CrashNoClauses (void/absurd)
  totalBugs              : Nat    -- CrashUnhandledInput (partial code)
  totalOptimizerArtifacts: Nat    -- CrashOptimizerNat (non-semantic)
  totalUnknown           : Nat    -- CrashUnknown (never exclude)
  functionsWithCrash     : Nat
```

## Output Formats

### Semantic Coverage JSON

```json
{
  "analysis": {
    "total_functions": 42,
    "total_canonical": 156,
    "total_excluded": 23,
    "total_bugs": 2,
    "total_optimizer_artifacts": 1,
    "total_unknown": 0,
    "functions_with_crash": 5
  },
  "functions": [
    {
      "function": "Main.safeHead",
      "total_canonical": 1,
      "total_impossible": 1,
      "executed_canonical": 1,
      "coverage_percent": 100.0
    },
    {
      "function": "Parser.parseExpr",
      "total_canonical": 8,
      "total_impossible": 0,
      "executed_canonical": 6,
      "coverage_percent": 75.0
    }
  ]
}
```

### Semantic Coverage Text

```
=== Semantic Coverage Report ===

Project Summary:
  Functions analyzed: 42
  Canonical cases: 156
  Excluded (void/absurd): 23
  Bugs (partial code): 2
  Optimizer artifacts: 1
  Unknown CRASHes: 0
  Functions with CRASH: 5

Per-function:
  Main.safeHead: 1/1 (100%) [excluded: 1]
  Parser.parseExpr: 6/8 (75%) [bugs: 0]
  Validator.check: 0/3 (0%) [excluded: 2]
```

## Requirements

- Idris2 0.8.0+

## Installation

```bash
git clone https://github.com/shogochiai/idris2-coverage
cd idris2-coverage
idris2 --build idris2-coverage.ipkg
```

## Project Structure

```
src/
├── Main.idr                    # CLI entry point
└── Coverage/
    ├── Types.idr               # Core types (CaseKind, SemanticCoverage, etc.)
    ├── SemanticCoverage.idr    # High-level API (runs --dumpcases internally)
    ├── DumpcasesParser.idr     # Low-level --dumpcases output parser
    ├── Aggregator.idr          # Coverage aggregation
    ├── Report.idr              # JSON/Text output
    ├── TestRunner.idr          # Test execution utilities
    └── Tests/
        └── AllTests.idr        # Unit tests
```

## License

MIT
