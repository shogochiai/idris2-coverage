# idris2-coverage

Type-driven code coverage analysis tool for Idris2.

Combines runtime profiling (via Chez Scheme) with static type analysis to provide comprehensive coverage metrics including state space analysis, linearity-aware path pruning, and complexity recommendations.

## Features

- **Runtime Coverage**: Traditional line/function coverage via Chez Scheme profiler
- **Branch Coverage**: Analyzes if/case/cond branches to identify untested code paths
- **State Space Analysis**: Estimates required test cases from type signatures
- **Linearity Support**: Handles Idris2's QTT (Quantitative Type Theory) annotations
- **Path Pruning**: Automatically detects and prunes early-exit paths (Nothing, Left, etc.)
- **Complexity Metrics**: Warns when functions should be split for better testability
- **Test Hints**: Generates actionable hints for missing tests with code templates

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

## Coverage Types

### 1. Runtime Coverage (Line/Function)

Traditional coverage measuring which functions were executed during tests.

```json
{
  "functions": [{
    "module": "Sample",
    "name": "add",
    "signature": "Int -> Int -> Int",
    "coverage_percent": 100.0,
    "called_by_tests": ["test_add", "test_integration"]
  }]
}
```

### 2. State Space Coverage (Type-Driven)

Estimates how many test cases are needed based on parameter types.

| Type | State Count | Representative Values |
|------|-------------|----------------------|
| `Bool` | 2 | True, False |
| `Maybe a` | 1 + \|a\| | Nothing, Just _ |
| `Either a b` | \|a\| + \|b\| | Left _, Right _ |
| `Nat` | 3 (bounded) | 0, 1, n |
| `String` | 3 (bounded) | "", "a", "abc" |

For a function `f : Bool -> Maybe Int -> String`:
- Estimated test cases = 2 × (1 + 3) = 8

### 3. Linearity-Aware Analysis

Idris2's QTT annotations affect coverage requirements:

| Quantity | Meaning | Coverage Impact |
|----------|---------|-----------------|
| `0` (Erased) | Compile-time only | No runtime tests needed |
| `1` (Linear) | Used exactly once | Eliminates "unused" paths |
| `ω` (Unrestricted) | Normal usage | Full state space |

```idris
-- Linear parameter: h must be consumed
closeFile : (1 h : FileHandle) -> IO ()
```

### 4. Path Pruning

Early-exit patterns are automatically detected and can be pruned:

```idris
process : Maybe a -> Maybe b -> Result
process Nothing  _        = defaultResult   -- Early exit (prunable)
process _        Nothing  = defaultResult   -- Early exit (prunable)
process (Just x) (Just y) = compute x y     -- Happy path
```

Without pruning: 2 × 2 = 4 test cases
With pruning: 2 test cases (1 early exit + 1 happy path)

### 5. Branch Coverage

Analyzes Scheme-level branch constructs (`if`, `case`, `cond`) to identify untested code paths.

```
Expression Coverage: 73.7% (13296/18034 expressions)
Branch Coverage:     33.6% (150/446 branches)
```

Branch coverage is complementary to expression coverage - it specifically tracks whether all paths through conditional logic were exercised.

#### Branch Types

| Type | Branches | Coverage Requirement |
|------|----------|---------------------|
| `if` | 2 (then/else) | Both branches must be taken |
| `case` | N patterns | Each pattern must be matched |
| `cond` | N conditions | Each condition must be satisfied |

#### Branch Coverage JSON

```json
{
  "total_branch_points": 217,
  "total_branches": 446,
  "covered_branches": 150,
  "branch_percent": 33.63
}
```

#### Branch-Specific Test Hints

For uncovered branches, actionable hints are generated:

```json
{
  "function": "PreludeC-45Types-u--foldr_Foldable_List",
  "line": 732,
  "branch_type": "if",
  "uncovered_path": "else-branch not taken",
  "suggested_input": "Provide input where condition is FALSE",
  "priority": "IMPORTANT",
  "rationale": "The false-case of this if expression was never executed"
}
```

#### Human-Readable Hint Output

```
=== Branch Coverage Improvement Hints ===

Uncovered branches: 56

--- IMPORTANT (should fix) ---
  * blodwen-lazy (line 43)
    Problem: else-branch not taken
    Solution: Provide input where condition is FALSE

  * PreludeC-45Types-u--foldr_Foldable_List (line 732)
    Problem: else-branch not taken
    Solution: Provide input where condition is FALSE
```

### 6. Test Hint Generation

For functions without tests, idris2-coverage generates actionable hints:

#### Happy Path Hints (Critical)

Minimal tests for basic functionality:

```json
{
  "category": "happy_path",
  "priority": "CRITICAL",
  "description": "Basic successful execution with valid inputs",
  "params": [
    {"name": "config", "value": "Just _", "rationale": "Typical valid value"},
    {"name": "input", "value": "\"test\"", "rationale": "Typical valid value"}
  ],
  "code_template": "test_process_happy : IO Bool\ntest_process_happy = do\n  let result = process (Just cfg) \"test\"\n  pure $ isExpected result\n"
}
```

#### Exhaustive Path Hints (Important → Optional)

Complete coverage including error paths and boundaries:

| Priority | Category | Example |
|----------|----------|---------|
| CRITICAL | Happy Path | Valid inputs, normal execution |
| CRITICAL | Linear Resource | Resource acquire/consume lifecycle |
| IMPORTANT | Error Path | Nothing, Left cases |
| NICE | Boundary | Empty string, zero, empty list |
| OPTIONAL | Combination | Full cartesian product of states |

#### Using Test Hints

```idris
import Coverage.TestHint
import Coverage.StateSpace

-- Generate hints for uncovered function
hints : FunctionTestHints
hints = generateTestHints defaultConfig analyzedFunc

-- Get minimal test suite (Critical + Important only)
minimal : List TestHint
minimal = minimalTestSuite hints

-- Generate test code
code : String
code = generateTestCode hints
```

#### JSON Output for Test Hints

```json
{
  "function": "processConfig",
  "signature": "Maybe Config -> String -> IO Result",
  "total_hints": 8,
  "critical_count": 2,
  "important_count": 3,
  "happy_path_hints": [...],
  "exhaustive_hints": [...]
}
```

## Output Format

### Extended JSON Schema

```json
{
  "functions": [{
    "module": "Sample",
    "name": "process",
    "signature": "(1 h : Handle) -> Maybe Config -> IO Result",
    "line_start": 10,
    "line_end": 25,
    "covered_lines": 12,
    "total_lines": 15,
    "coverage_percent": 80.0,
    "called_by_tests": ["test_process_success", "test_process_failure"],
    "state_space": {
      "estimated_cases": 6,
      "actual_cases": 4,
      "state_space_coverage": 66.7,
      "linear_params": ["h"],
      "pruned_paths": ["Nothing"]
    },
    "complexity": {
      "param_count": 2,
      "branch_count": 3,
      "should_split": false
    }
  }],
  "modules": [{
    "path": "src/Sample.idr",
    "functions_total": 4,
    "functions_covered": 3,
    "line_coverage_percent": 75.0,
    "state_space_coverage_percent": 70.0
  }],
  "project": {
    "total_functions": 4,
    "covered_functions": 3,
    "line_coverage_percent": 75.0,
    "state_space_coverage_percent": 70.0,
    "complexity_warnings": 1
  }
}
```

## How It Works

### Runtime Analysis

1. **Profile Collection**: Parses Chez Scheme's `profile.html` from `--profile` builds
2. **Scheme Mapping**: Converts Scheme names (e.g., `SampleC-45Module-add`) to Idris modules
3. **Test Attribution**: Runs each test individually to compute `called_by_tests`

### Static Analysis

1. **Type Extraction**: Parses function signatures from Idris2 output
2. **State Space Calculation**: Computes |Type| for each parameter
3. **Path Analysis**: Identifies early exits (Nothing, Left, Nil patterns)
4. **Linearity Processing**: Handles Q0/Q1/QW quantity annotations
5. **Complexity Scoring**: Flags functions exceeding thresholds

### Naming Convention

Idris module names are converted to Scheme format:
- `Sample` → `Sample-functionName`
- `Audit.Orchestrator` → `AuditC-45Orchestrator-functionName`

## Project Structure

```
src/
├── Main.idr                 # CLI entry point
└── Coverage/
    ├── Types.idr            # Core type definitions (extended)
    ├── Collector.idr        # profile.html parsing
    ├── SourceAnalyzer.idr   # Idris source analysis
    ├── TestRunner.idr       # Test execution with profiling
    ├── Aggregator.idr       # called_by_tests computation
    ├── Report.idr           # JSON/Text output
    ├── Linearity.idr        # QTT linearity analysis
    ├── TypeAnalyzer.idr     # Type signature parsing
    ├── StateSpace.idr       # State space calculation
    ├── PathAnalysis.idr     # Early exit detection & pruning
    ├── Complexity.idr       # Complexity metrics & warnings
    ├── TestHint.idr         # Test hint generation
    └── Tests/               # Unit tests
```

## Module Overview

### Core Modules (v0.1.0)

| Module | Purpose |
|--------|---------|
| `Types` | Data types for coverage reports |
| `Collector` | Parse Chez Scheme profiler output |
| `SourceAnalyzer` | Extract functions from .idr files |
| `TestRunner` | Execute tests with profiling |
| `Aggregator` | Combine results, compute called_by_tests |
| `Report` | Generate JSON/text output |

### Analysis Modules (v0.2.0)

| Module | Purpose |
|--------|---------|
| `Linearity` | Handle QTT quantities (0/1/ω) |
| `TypeAnalyzer` | Parse type signatures, resolve types |
| `StateSpace` | Calculate state counts, suggest test cases |
| `PathAnalysis` | Detect early exits, prune paths |
| `Complexity` | Score complexity, recommend splits |

### Test Generation Module (v0.3.0)

| Module | Purpose |
|--------|---------|
| `TestHint` | Generate test hints and code templates |

## Configuration

Default thresholds (can be customized):

```idris
defaultConfig : StateSpaceConfig
defaultConfig = MkStateSpaceConfig
  { equivalenceClassLimit = 10    -- Max states per parameter
  , maxTotalStates = 1000         -- Cap on total state space
  , recursionDepth = 3            -- Max depth for recursive types
  , pruneEarlyExits = True        -- Prune Nothing/Left paths
  }

defaultComplexityConfig : ComplexityConfig
defaultComplexityConfig = MkComplexityConfig
  { maxParams = 4                 -- Warn if > 4 parameters
  , maxStateSpace = 50            -- Warn if state space > 50
  , maxPatternDepth = 3           -- Warn if deeply nested
  , maxBranches = 10              -- Warn if > 10 branches
  , warnLinearOverload = True     -- Warn if > 2 linear params
  }
```

## Running Tests

```bash
idris2 -o test-runner -p idris2-coverage src/Coverage/Tests.idr
./build/exec/test-runner
```

## Integration with lazy-idris

This library can be used standalone or as a dependency for higher-level coverage analysis.

### API Endpoints

```idris
-- From Coverage.Collector
export parseBranchCoverage : String -> List BranchPoint
export summarizeBranchCoverage : List BranchPoint -> BranchCoverageSummary
export summarizeBranchCoverageWithFunctions : List (String, Nat) -> List BranchPoint -> BranchCoverageSummary
export parseSchemeDefs : String -> List (String, Nat)

-- From Coverage.TestHint
export generateBranchHints : BranchCoverageSummary -> List BranchHint
export summarizeBranchHints : List BranchHint -> BranchHintSummary
export branchHintsToText : BranchHintSummary -> String
export branchHintsToJson : List BranchHint -> String

-- From Coverage.Report
export branchCoverageSummaryJson : BranchCoverageSummary -> String
export branchPointJson : BranchPoint -> String

-- From Coverage.Aggregator
export aggregateProjectWithBranches : List ModuleCoverage -> BranchCoverageSummary -> ProjectCoverage
```

### Example: Branch Coverage Analysis

```idris
import Coverage.Types
import Coverage.Collector
import Coverage.TestHint
import System.File

analyzeCoverage : String -> String -> IO ()
analyzeCoverage htmlPath ssPath = do
  Right htmlContent <- readFile htmlPath
    | Left err => putStrLn "Error reading HTML"
  Right ssContent <- readFile ssPath
    | Left err => putStrLn "Error reading SS"

  -- 1. Parse function definitions from Scheme source
  let funcDefs = parseSchemeDefs ssContent

  -- 2. Parse branch coverage from annotated HTML
  let branchPoints = parseBranchCoverage htmlContent

  -- 3. Get summary with function associations
  let summary = summarizeBranchCoverageWithFunctions funcDefs branchPoints

  -- 4. Generate hints for uncovered branches
  let hints = generateBranchHints summary
  let hintSummary = summarizeBranchHints hints

  -- 5. Output
  putStrLn $ "Branch Coverage: " ++ show summary.branchPercent ++ "%"
  putStrLn $ "Uncovered branches: " ++ show (length hints)
  putStrLn $ branchHintsToText hintSummary
```

### Data Flow

```
lazy-idris audit
    │
    ├── Runs tests with --profile
    │
    ├── Gets audit-tests.ss.html (expression coverage)
    │
    └── Calls idris2-coverage:
            │
            ├── parseSchemeDefs(ss) → funcDefs
            │
            ├── parseBranchCoverage(html) → branchPoints
            │
            ├── summarizeBranchCoverageWithFunctions(funcDefs, branchPoints)
            │   └── BranchCoverageSummary { branchPercent, uncoveredBranches }
            │
            ├── generateBranchHints(summary)
            │   └── List BranchHint { function, line, problem, suggestion }
            │
            └── Output: JSON/Text with actionable hints
```

### State Space Analysis

```idris
import Coverage.StateSpace
import Coverage.Linearity

-- Analyze a function's state space
analyzeMyFunc : AnalyzedFunction -> FunctionStateSpaceAnalysis
analyzeMyFunc func = analyzeStateSpace defaultConfig func []

-- Generate test hints for uncovered functions
getTestHints : List AnalyzedFunction -> List FunctionCoverage -> List FunctionTestHints
getTestHints funcs coverages = generateHintsForUncovered defaultConfig funcs coverages
```

## Workflow: From Coverage Gaps to Tests

1. **Run coverage analysis** to identify uncovered functions
2. **Generate test hints** for functions with 0% coverage
3. **Start with Critical hints** (happy path + linear resources)
4. **Add Important hints** (error handling)
5. **Optionally add Nice/Optional hints** for thorough coverage

```bash
# 1. Generate coverage report
idris2-cov --format json -o coverage.json myproject.ipkg

# 2. Generate test hints for uncovered functions
idris2-cov --hints --output hints.json myproject.ipkg

# 3. Use hints to write tests (or feed to LLM for code generation)
```

The test hints provide structured information that can be:
- Used directly by developers to write tests
- Fed to an LLM for automated test code generation
- Integrated into CI pipelines for coverage gap reporting

## License

MIT
