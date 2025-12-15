# idris2-coverage

**Semantic coverage library** for Idris2. Uses `--dumpcases` output to measure canonical case coverage with type-awareness.

## Quick Start

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

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     SEMANTIC COVERAGE                                │
│  idris2 --dumpcases myproject.ipkg                                  │
│    → CaseTree output → DumpcasesParser                              │
│    → Canonical vs Impossible vs NotCovered classification           │
│    → Coverage = executed_canonical / total_canonical                │
└─────────────────────────────────────────────────────────────────────┘
                                  ↓
┌─────────────────────────────────────────────────────────────────────┐
│                        LAZY INTEGRATION                              │
│  Lazy STI Parity → runCoveragePass                                  │
│    → Gaps for uncovered canonical cases                             │
│    → Signal.Adaptor for real-time coverage data                     │
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

## API Reference

### DumpcasesParser

```idris
-- Parse --dumpcases output
parseDumpcasesFile : String -> List CompiledFunction

-- Analyze a single function
analyzeFunction : String -> Maybe CompiledFunction

-- Aggregate analysis
aggregateAnalysis : List CompiledFunction -> SemanticAnalysis

-- Convert to SemanticCoverage
toSemanticCoverage : CompiledFunction -> SemanticCoverage

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
│  lazy core ask                                                       │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ↓
┌─────────────────────────────────────────────────────────────────────┐
│  LazyCore/src/Ask/TestAndCoverage.idr                               │
│                                                                      │
│  runCoveragePass : AskOptions -> IO (List Gap, StepStatus)          │
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
-- Semantic coverage is the only mode
runCoveragePass : AskOptions -> IO (List Gap, StepStatus)
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
├── Main.idr                 # CLI entry point
└── Coverage/
    ├── Types.idr            # Core types (CaseKind, SemanticCoverage, etc.)
    ├── DumpcasesParser.idr  # --dumpcases parser
    ├── Aggregator.idr       # Coverage aggregation
    ├── Report.idr           # JSON/Text output
    ├── TestRunner.idr       # Test execution utilities
    └── Tests/
        └── AllTests.idr     # Unit tests
```

## License

MIT
