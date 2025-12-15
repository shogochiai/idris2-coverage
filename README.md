# idris2-coverage

**Code coverage library** for Idris2. Provides two coverage modes:

1. **Legacy Mode**: Expression/branch coverage from Chez Scheme profiler (`.ss.html`)
2. **Semantic Mode** (Phase 7): Canonical case coverage from `--dumpcases` output

## Quick Start

### Semantic Coverage (Recommended)

```idris
import Coverage.DumpcasesParser
import Coverage.Types

main : IO ()
main = do
  -- Run idris2 --dumpcases to get case analysis
  Right content <- readFile "/tmp/dumpcases_output.txt"
    | Left _ => putStrLn "Error reading dumpcases"

  let funcs = parseDumpcasesFile content
  let analysis = aggregateAnalysis funcs

  putStrLn $ "Canonical cases: " ++ show analysis.totalCanonical
  putStrLn $ "Impossible (excluded): " ++ show analysis.totalImpossible
  putStrLn $ "Not-covered (bugs): " ++ show analysis.totalNotCovered
```

### Legacy Coverage (Branch/Expression)

```idris
import Coverage.UnifiedRunner
import Coverage.Types

main : IO ()
main = do
  result <- runTestsWithCoverage "." ["My.Tests.AllTests"] 120
  case result of
    Left err => putStrLn $ "Error: " ++ err
    Right report => do
      putStrLn $ "Tests: " ++ show report.passedTests ++ "/" ++ show report.totalTests
      putStrLn $ "Branch coverage: " ++ show report.branchCoverage.branchPercent ++ "%"
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     SEMANTIC COVERAGE (Phase 7)                      │
│  idris2 --dumpcases myproject.ipkg                                  │
│    → CaseTree output → DumpcasesParser                              │
│    → Canonical vs Impossible vs NotCovered classification           │
│    → Coverage = executed_canonical / total_canonical                │
└─────────────────────────────────────────────────────────────────────┘
                                  ↓
┌─────────────────────────────────────────────────────────────────────┐
│                        LAZY INTEGRATION                              │
│  Lazy STI Parity → runSemanticCoveragePass                          │
│    → Gaps for uncovered canonical cases                             │
│    → Signal.Adaptor for real-time coverage data                     │
└─────────────────────────────────────────────────────────────────────┘
                                  ↓
┌─────────────────────────────────────────────────────────────────────┐
│                     LEGACY COVERAGE (Optional)                       │
│  runTestsWithCoverage → .ss.html parsing                            │
│    → Expression/Branch coverage from Chez profiler                  │
└─────────────────────────────────────────────────────────────────────┘
```

## Semantic Coverage (Phase 7)

### What is Semantic Coverage?

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
-- From Coverage.Types
data CrashReason
  = CrashImpossible    -- "Impossible case encountered" → exclude from denominator
  | CrashNotCovered    -- "case not covered" → bug, keep in denominator
  | CrashNoClauses     -- "No clauses in..." → exclude from denominator
  | CrashOther String  -- Unknown → keep in denominator

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

### API Reference: DumpcasesParser

```idris
-- Parse --dumpcases output
parseDumpcasesFile : String -> List CompiledFunction

-- Analyze a single function
analyzeFunction : String -> Maybe CompiledFunction

-- Aggregate analysis
aggregateAnalysis : List CompiledFunction -> SemanticAnalysis

-- Convert to SemanticCoverage
toSemanticCoverage : CompiledFunction -> SemanticCoverage

-- Runtime hit mapping (Phase 7.6)
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

-- Semantic coverage per function
record SemanticCoverage where
  constructor MkSemanticCoverage
  funcName          : String
  totalCanonical    : Nat    -- Denominator
  totalImpossible   : Nat    -- Excluded from denominator
  executedCanonical : Nat    -- Numerator (from runtime)

-- Project-level analysis
record SemanticAnalysis where
  constructor MkSemanticAnalysis
  totalFunctions      : Nat
  totalCanonical      : Nat
  totalImpossible     : Nat
  totalNotCovered     : Nat    -- Bugs
  functionsWithCrash  : Nat
```

## Lazy Integration

### Integration Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                           LAZY CLI                                   │
│  lazy core ask --coverage-mode semantic                             │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ↓
┌─────────────────────────────────────────────────────────────────────┐
│  LazyCore/src/Ask/TestAndCoverage.idr                               │
│                                                                      │
│  runSemanticCoveragePass : AskOptions -> IO (List Gap, StepStatus)  │
│    1. idris2 --dumpcases → parseDumpcasesFile                       │
│    2. runTestsWithCoverage → runtime hits                           │
│    3. semanticCoverageWithHits → coverage %                         │
│    4. Convert uncovered → Gaps                                      │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ↓
┌─────────────────────────────────────────────────────────────────────┐
│  LazyCore/src/Coverage/Report.idr                                   │
│                                                                      │
│  semanticReportJson : SemanticAnalysis -> List SemanticCoverage     │
│                     -> String                                        │
│  semanticReportText : SemanticAnalysis -> List SemanticCoverage     │
│                     -> String                                        │
└─────────────────────────────────────────────────────────────────────┘
```

### Usage in Lazy STI Parity

```idris
-- LazyCore imports idris2-coverage
import Coverage.DumpcasesParser
import Coverage.Types
import Coverage.TestRunner

-- In STI Parity Step 4 (Test & Coverage)
runCoveragePass : AskOptions -> IO (List Gap, StepStatus)
runCoveragePass opts =
  case opts.coverageMode of
    Legacy   => runBranchCoveragePass opts    -- .ss.html based
    Semantic => runSemanticCoveragePass opts  -- --dumpcases based
```

### Gap Generation

```idris
-- Uncovered canonical cases become Gaps
semanticCoverageToGaps : SemanticCoverage -> List Gap
semanticCoverageToGaps sc =
  let uncovered = sc.totalCanonical `minus` sc.executedCanonical
  in if uncovered > 0
       then [MkGap
               ("semantic:uncovered:" ++ sc.funcName)
               "test-and-coverage"
               (MkModulePath "core" "LazyCore" [] sc.funcName)
               (show sc.executedCanonical ++ "/" ++ show sc.totalCanonical ++ " canonical cases")
               Warning
               Nothing Nothing]
       else []
```

### Signal.Adaptor Interface (Future)

For real-time coverage data streaming:

```idris
-- Signal.Adaptor provides reactive coverage updates
-- (Planned for deeper Lazy integration)

record CoverageSignal where
  constructor MkCoverageSignal
  funcName   : String
  canonical  : Nat
  executed   : Nat
  timestamp  : Integer

-- Adaptor converts coverage events to Signals
coverageToSignal : SemanticCoverage -> CoverageSignal
```

## Output Formats

### Semantic Coverage JSON

```json
{
  "analysis": {
    "total_functions": 42,
    "total_canonical": 156,
    "total_impossible": 23,
    "total_not_covered": 2,
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
  Impossible cases (excluded): 23
  Not-covered cases (bugs): 2
  Functions with CRASH: 5

Per-function:
  Main.safeHead: 1/1 (100%) [impossible: 1]
  Parser.parseExpr: 6/8 (75%) [impossible: 0]
  Validator.check: 0/3 (0%) [impossible: 2]
```

### Legacy Branch Coverage JSON

```json
{
  "total_branch_points": 217,
  "total_branches": 446,
  "covered_branches": 150,
  "branch_percent": 33.63
}
```

## Legacy Coverage Mode

The original coverage mode using Chez Scheme profiler output.

### Features

- **Expression Coverage**: Per-expression execution counts
- **Branch Coverage**: Analyzes `if`/`case`/`cond` constructs
- **Test Hints**: Actionable suggestions for improving coverage
- **Function Mapping**: Associates Scheme code to Idris functions

### Unified Runner API

```idris
-- Run tests with profiling and return combined report
runTestsWithCoverage : (projectDir : String)
                     -> (testModules : List String)
                     -> (timeout : Nat)
                     -> IO (Either String TestCoverageReport)

-- Test modules must export: runAllTests : IO ()
-- Output format: [PASS] TestName or [FAIL] TestName: message
```

### Manual Analysis

```idris
import Coverage.Collector
import Coverage.TestHint

analyzeCoverage : String -> String -> IO ()
analyzeCoverage ssHtmlPath ssPath = do
  Right html <- readFile ssHtmlPath | Left _ => putStrLn "Error"
  Right ss <- readFile ssPath | Left _ => putStrLn "Error"

  let funcDefs = parseSchemeDefs ss
  let branchPoints = parseBranchCoverage html
  let summary = summarizeBranchCoverageWithFunctions funcDefs branchPoints
  let hints = generateBranchHints summary

  putStrLn $ "Branch Coverage: " ++ show summary.branchPercent ++ "%"
  putStrLn $ branchHintsToText (summarizeBranchHints hints)
```

## Requirements

- Idris2 0.8.0+
- Chez Scheme 10.0+ (for legacy mode profiler output)

## Installation

```bash
git clone https://github.com/shogochiai/idris2-coverage
cd idris2-coverage
idris2 --build idris2-coverage.ipkg
```

## Project Structure

```
src/
├── Main.idr                 # CLI entry point
└── Coverage/
    ├── Types.idr            # Core types (CaseKind, SemanticCoverage, etc.)
    ├── DumpcasesParser.idr  # NEW: --dumpcases parser (Phase 7)
    ├── UnifiedRunner.idr    # High-level API: runTestsWithCoverage
    ├── Collector.idr        # .ss.html parsing, branch detection
    ├── Aggregator.idr       # Coverage aggregation
    ├── Report.idr           # JSON/Text output (+ semantic reports)
    ├── TestHint.idr         # Hint generation for uncovered code
    ├── TestRunner.idr       # Test execution utilities
    └── Tests/
        └── AllTests.idr     # Unit tests
```

## Comparison: Semantic vs Legacy

| Aspect | Semantic (Phase 7) | Legacy |
|--------|-------------------|--------|
| Source | `--dumpcases` | `.ss.html` profiler |
| Granularity | Case patterns | Expressions/branches |
| Type-awareness | Yes (impossible excluded) | No |
| Runtime needed | Optional (for executed count) | Required |
| Idris-native | Yes | Scheme-based |

## Limitations

1. **Semantic Mode**: Requires `--dumpcases` flag support in Idris2
2. **Legacy Mode**: Chez Scheme backend only
3. **Name Mapping**: Legacy mode uses Scheme-mangled names
4. **Unified Runner**: Test modules must export `runAllTests : IO ()`

## License

MIT
