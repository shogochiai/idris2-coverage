||| High-level Test Coverage API
|||
||| This module provides a simple interface for analyzing Idris2 projects:
|||
|||   analyzeProject : String -> IO (Either String TestAnalysis)
|||   analyzeProjectWithHits : String -> List String -> IO (Either String TestCoverage)
|||
||| The API handles --dumpcases invocation internally, so users don't need to
||| know the non-obvious syntax: idris2 --dumpcases <output> --build <package.ipkg>
|||
||| Issue #5 & #6: This is the recommended entry point for idris2-coverage users.
module Coverage.TestCoverage

import Coverage.Types
import Coverage.DumpcasesParser
import Coverage.Collector
import Coverage.UnifiedRunner

import Data.List
import Data.List1
import Data.Maybe
import Data.String
import System
import System.File
import System.Clock

%default covering

-- =============================================================================
-- Helper: Split Path into Directory and Filename
-- =============================================================================

||| Split "path/to/project.ipkg" into ("path/to", "project.ipkg")
||| Handles edge cases like just "project.ipkg" -> (".", "project.ipkg")
splitIpkgPath : String -> (String, String)
splitIpkgPath path =
  let parts = forget $ split (== '/') path
  in case parts of
       [] => (".", path)
       [x] => (".", x)
       _ => case (initLast parts) of
              Nothing => (".", path)
              Just (dirParts, lastPart) => (fastConcat $ intersperse "/" dirParts, lastPart)
  where
    -- Safe init + last that returns Maybe
    initLast : List a -> Maybe (List a, a)
    initLast [] = Nothing
    initLast [x] = Just ([], x)
    initLast (x :: xs) = case initLast xs of
      Nothing => Just ([], x)
      Just (ys, z) => Just (x :: ys, z)

-- =============================================================================
-- High-Level API (Issue #5)
-- =============================================================================

||| Analyze project for semantic coverage - static analysis only
|||
||| This is the recommended entry point. It:
||| 1. Runs idris2 --dumpcases internally with correct syntax
||| 2. Parses the output to classify canonical vs impossible cases
||| 3. Returns TestAnalysis with the breakdown
|||
||| @ipkgPath - Path to the .ipkg file (e.g., "myproject.ipkg" or "path/to/project/project.ipkg")
||| @returns  - Either error message or TestAnalysis
public export
analyzeProject : (ipkgPath : String) -> IO (Either String TestAnalysis)
analyzeProject ipkgPath = do
  -- Extract directory and ipkg name
  let (dir, ipkgName) = splitIpkgPath ipkgPath

  -- Run dumpcases
  result <- runDumpcasesDefault dir ipkgName
  case result of
    Left err => pure $ Left err
    Right content => do
      let funcs = parseDumpcasesFile content
      pure $ Right $ aggregateAnalysis funcs

||| Get detailed function-level analysis
|||
||| @ipkgPath - Path to the .ipkg file
||| @returns  - Either error or list of CompiledFunction with case classifications
public export
analyzeProjectFunctions : (ipkgPath : String) -> IO (Either String (List CompiledFunction))
analyzeProjectFunctions ipkgPath = do
  let (dir, ipkgName) = splitIpkgPath ipkgPath
  result <- runDumpcasesDefault dir ipkgName
  case result of
    Left err => pure $ Left err
    Right content => pure $ Right $ parseDumpcasesFile content

-- =============================================================================
-- Combined Analysis with Runtime Hits (Issue #6)
-- =============================================================================

||| Analyze project with runtime profiler data
|||
||| This combines:
||| 1. Static analysis from --dumpcases (canonical vs impossible classification)
||| 2. Runtime hits from .ss.html profiler output
|||
||| @ipkgPath    - Path to the .ipkg file
||| @testModules - List of test module names to run (e.g., ["Tests.AllTests"])
||| @returns     - Either error or TestCoverage with executed counts
public export
analyzeProjectWithHits : (ipkgPath : String)
                       -> (testModules : List String)
                       -> IO (Either String TestCoverage)
analyzeProjectWithHits ipkgPath testModules = do
  let (projectDir, ipkgName) = splitIpkgPath ipkgPath

  -- Step 1: Get static analysis from --dumpcases
  dumpResult <- runDumpcasesDefault projectDir ipkgName
  case dumpResult of
    Left err => pure $ Left $ "Dumpcases failed: " ++ err
    Right dumpContent => do
      let funcs = parseDumpcasesFile dumpContent
      let analysis = aggregateAnalysis funcs

      -- Step 2: Run tests with profiler
      testResult <- runTestsWithCoverage projectDir testModules 120
      case testResult of
        Left testErr => do
          -- Return static analysis only with 0 executed
          pure $ Right $ MkTestCoverage
            "project"
            analysis.totalCanonical
            analysis.totalExcluded
            0
        Right report => do
          -- Step 3: Extract executed count from profiler
          -- Use coveredBranches as approximation for executed canonical cases
          let executed = report.branchCoverage.coveredBranches
          pure $ Right $ MkTestCoverage
            "project"
            analysis.totalCanonical
            analysis.totalExcluded
            executed

-- =============================================================================
-- Per-Function Analysis with Runtime Hits (Pragmatic v1.0)
-- =============================================================================

||| Detailed per-function pragmatic coverage with runtime hits
||| Follows the "Absurd を分母から除外" principle:
|||   - Coverage % = executed/canonical (denominator excludes impossible)
|||   - excluded* fields: safe to exclude from denominator (100% achievable)
|||   - bug/unknown fields: CI signals (not in denominator, but flagged)
public export
record FunctionTestCoverage where
  constructor MkFunctionTestCoverage
  funcName           : String
  moduleName         : String

  -- Coverage の分母/分子（ここだけが「カバレッジ」本体）
  totalCanonical     : Nat
  executedCanonical  : Nat
  coveragePercent    : Double

  -- 分母から除外する（= 100% を阻害しない）要素
  excludedNoClauses  : Nat    -- void/uninhabited
  excludedOptimizer  : Nat    -- Nat case not covered

  -- CI の別軸シグナル（分母に混ぜない）
  bugUnhandledInput  : Nat    -- partial code (should fix)
  unknownCrash       : Nat    -- conservative bucket (investigate)

public export
Show FunctionTestCoverage where
  show fsc = fsc.funcName ++ ": " ++ show fsc.executedCanonical
          ++ "/" ++ show fsc.totalCanonical
          ++ " (" ++ show (cast {to=Int} fsc.coveragePercent) ++ "%)"

-- =============================================================================
-- Bucket Classification Functions (Pragmatic v1.0)
-- =============================================================================

-- Practical: safe to exclude from denominator
--   - NoClauses: void/uninhabited bodies
--   - OptimizerNat: Nat->Int optimizer artifact
isExcludedCaseSC : CompiledCase -> Bool
isExcludedCaseSC c = case c.kind of
  NonCanonical CrashNoClauses    => True
  NonCanonical CrashOptimizerNat => True
  _ => False

countCanonicalCasesSC : CompiledFunction -> Nat
countCanonicalCasesSC func = length $ filter (\c => c.kind == Canonical) func.cases

-- Detailed count functions for breakdown
countExcludedNoClausesSC : CompiledFunction -> Nat
countExcludedNoClausesSC func =
  length $ filter (\c => case c.kind of
    NonCanonical CrashNoClauses => True
    _ => False
  ) func.cases

countExcludedOptimizerSC : CompiledFunction -> Nat
countExcludedOptimizerSC func =
  length $ filter (\c => case c.kind of
    NonCanonical CrashOptimizerNat => True
    _ => False
  ) func.cases

countBugUnhandledInputSC : CompiledFunction -> Nat
countBugUnhandledInputSC func =
  length $ filter (\c => case c.kind of
    NonCanonical CrashUnhandledInput => True
    _ => False
  ) func.cases

countUnknownCrashSC : CompiledFunction -> Nat
countUnknownCrashSC func =
  length $ filter (\c => case c.kind of
    NonCanonical (CrashUnknown _) => True
    _ => False
  ) func.cases

-- 互換のために残す（旧名）: NoClauses + Optimizer
countExcludedCasesSC : CompiledFunction -> Nat
countExcludedCasesSC func =
  countExcludedNoClausesSC func + countExcludedOptimizerSC func

||| Convert CompiledFunction to FunctionTestCoverage with hits (Pragmatic v1.0)
public export
functionToTestCoverage : CompiledFunction -> Nat -> FunctionTestCoverage
functionToTestCoverage f executed =
  let canonical = countCanonicalCasesSC f in

  let exclNoClauses = countExcludedNoClausesSC f in
  let exclOptimizer = countExcludedOptimizerSC f in

  let bugUnhandled  = countBugUnhandledInputSC f in
  let unknownCrash  = countUnknownCrashSC f in

  let pct = if canonical == 0
            then 100.0
            else cast executed / cast canonical * 100.0

  in MkFunctionTestCoverage
       f.fullName
       f.moduleName
       canonical
       executed
       pct
       exclNoClauses
       exclOptimizer
       bugUnhandled
       unknownCrash

-- =============================================================================
-- High Impact Targets (Pragmatic v1.0)
-- =============================================================================

||| Classification of high-impact coverage gaps
public export
data HighImpactKind
  = HIT_UntestedCanonical   -- canonical > 0 && executed == 0
  | HIT_BugUnhandledInput   -- bugUnhandledInput > 0
  | HIT_UnknownCrash        -- unknownCrash > 0

public export
Show HighImpactKind where
  show HIT_UntestedCanonical = "untested_canonical"
  show HIT_BugUnhandledInput = "bug_unhandled_input"
  show HIT_UnknownCrash      = "unknown_crash"

public export
Eq HighImpactKind where
  HIT_UntestedCanonical == HIT_UntestedCanonical = True
  HIT_BugUnhandledInput == HIT_BugUnhandledInput = True
  HIT_UnknownCrash      == HIT_UnknownCrash      = True
  _ == _ = False

||| A high-impact target for coverage improvement
public export
record HighImpactTarget where
  constructor MkHighImpactTarget
  kind         : HighImpactKind
  funcName     : String
  moduleName   : String
  branchCount  : Nat     -- total canonical branches OR bug/unknown count
  executedCount : Nat    -- branches executed at runtime (from .ss.html)
  severity     : Double  -- branchCount/executedCount ratio (Inf if executedCount=0)
  note         : String  -- human-readable explanation

||| Format severity as string (handles Inf case)
export
showSeverity : Double -> String
showSeverity s = if s > 1.0e308 then "Inf"
                 else let rounded = cast {to=Int} (s * 100.0)
                      in show (cast {to=Double} rounded / 100.0)

public export
Show HighImpactTarget where
  show t = "[" ++ show t.kind ++ "] " ++ t.funcName
        ++ " (executed=" ++ show t.executedCount ++ "/" ++ show t.branchCount
        ++ ", severity=" ++ showSeverity t.severity ++ ")"

||| Calculate severity score as branchCount/executedCount ratio
||| Returns Infinity (1e309) if executedCount = 0, otherwise ratio with 2 decimal places
||| For bugs/unknown: use branchCount as severity (they don't have executed concept)
public export
severityRatio : Nat -> Nat -> Double
severityRatio branchCount executedCount =
  if executedCount == 0
     then 1.0e309  -- Infinity
     else cast branchCount / cast executedCount

||| Extract high-impact targets from a FunctionTestCoverage
||| Returns 0-3 targets depending on which coverage issues exist
||| Now includes executedCount from runtime profiler
||| Severity = branchCount / executedCount (Inf if executedCount = 0)
public export
targetsFromFunction : FunctionTestCoverage -> List HighImpactTarget
targetsFromFunction fsc =
  let -- Calculate untested branches (gap between total and executed)
      untestedBranches = if fsc.totalCanonical > fsc.executedCanonical
                         then fsc.totalCanonical `minus` fsc.executedCanonical
                         else 0
      -- Only flag as untested if there are actual untested branches
      untested = if untestedBranches > 0
                 then [MkHighImpactTarget
                         HIT_UntestedCanonical
                         fsc.funcName
                         fsc.moduleName
                         fsc.totalCanonical
                         fsc.executedCanonical
                         (severityRatio fsc.totalCanonical fsc.executedCanonical)
                         ("Function has " ++ show untestedBranches ++ " untested branches")]
                 else []
      -- Bugs: severity = Inf (always highest priority)
      bugs = if fsc.bugUnhandledInput > 0
             then [MkHighImpactTarget
                     HIT_BugUnhandledInput
                     fsc.funcName
                     fsc.moduleName
                     fsc.bugUnhandledInput
                     0  -- bugs don't have "executed" concept
                     1.0e309  -- Infinity - bugs are always highest priority
                     "Partial code: CRASH 'Unhandled input' detected"]
             else []
      -- Unknown: severity = Inf (needs investigation)
      unknown = if fsc.unknownCrash > 0
                then [MkHighImpactTarget
                        HIT_UnknownCrash
                        fsc.funcName
                        fsc.moduleName
                        fsc.unknownCrash
                        0  -- unknown crashes don't have "executed" concept
                        1.0e309  -- Infinity - unknown needs investigation
                        "Unknown CRASH message - investigate"]
                else []
  in untested ++ bugs ++ unknown

||| Sort targets by severity (descending), then by branchCount (descending) for ties
public export
sortTargets : List HighImpactTarget -> List HighImpactTarget
sortTargets = sortBy compareSeverity
  where
    compareSeverity : HighImpactTarget -> HighImpactTarget -> Ordering
    compareSeverity a b =
      case compare b.severity a.severity of
        EQ => compare b.branchCount a.branchCount  -- secondary sort by branchCount
        other => other

||| Check if function name is compiler-generated
||| Patterns: {csegen:N}, {eta:N}, _builtin.*, prim__*
||| See docs/compiler-generated-functions.md for full reference
isCompilerGenerated : String -> Bool
isCompilerGenerated name =
     isPrefixOf "{" name          -- MN names: {csegen:N}, {eta:N}, etc.
  || isPrefixOf "_builtin." name  -- Builtin constructors
  || isPrefixOf "prim__" name     -- Primitive operations

||| Get top K high-impact targets from list of functions
||| Filters out compiler-generated functions ({csegen:*}, etc.)
public export
topKTargets : Nat -> List FunctionTestCoverage -> List HighImpactTarget
topKTargets k funcs =
  let allTargets = concatMap targetsFromFunction funcs
      -- Filter out compiler-generated functions
      userTargets = filter (not . isCompilerGenerated . funcName) allTargets
      sorted = sortTargets userTargets
  in take k sorted

-- =============================================================================
-- Report Generation
-- =============================================================================

||| Generate test coverage summary as text
||| Generate test coverage summary as text
||| Based on dunham's classification from Idris2 community:
|||   - Excluded (NoClauses): void etc, safe to exclude from denominator
|||   - Bugs (UnhandledInput): partial code, coverage issue
|||   - OptimizerArtifacts (Nat case): non-semantic, warn separately
|||   - Unknown: conservative, never exclude
public export
formatTestAnalysis : TestAnalysis -> String
formatTestAnalysis a = unlines
  [ "=== Test Coverage Report ==="
  , ""
  , "Project Summary:"
  , "  Functions analyzed: " ++ show a.totalFunctions
  , "  Canonical cases: " ++ show a.totalCanonical
  , "  Excluded (NoClauses): " ++ show a.totalExcluded
  , "  Bugs (UnhandledInput): " ++ show a.totalBugs
  , "  Optimizer artifacts (Nat): " ++ show a.totalOptimizerArtifacts
  , "  Unknown CRASHes: " ++ show a.totalUnknown
  , "  Functions with CRASH: " ++ show a.functionsWithCrash
  ]

||| Generate test coverage with hits as text
public export
formatTestCoverage : TestCoverage -> String
formatTestCoverage sc =
  let pct = testCoveragePercent sc
  in unlines
    [ "=== Test Coverage Report ==="
    , ""
    , "Coverage: " ++ show sc.executedCanonical
               ++ "/" ++ show sc.totalCanonical
               ++ " (" ++ show (cast {to=Int} pct) ++ "%)"
    , "Impossible cases (excluded): " ++ show sc.totalImpossible
    ]

-- =============================================================================
-- JSON Output
-- =============================================================================

||| Generate test analysis as JSON
public export
testAnalysisToJson : TestAnalysis -> String
testAnalysisToJson a = unlines
  [ "{"
  , "  \"total_functions\": " ++ show a.totalFunctions ++ ","
  , "  \"total_canonical\": " ++ show a.totalCanonical ++ ","
  , "  \"total_excluded\": " ++ show a.totalExcluded ++ ","
  , "  \"total_bugs\": " ++ show a.totalBugs ++ ","
  , "  \"total_optimizer_artifacts\": " ++ show a.totalOptimizerArtifacts ++ ","
  , "  \"total_unknown\": " ++ show a.totalUnknown ++ ","
  , "  \"total_compiler_generated\": " ++ show a.totalCompilerGenerated ++ ","
  , "  \"functions_with_crash\": " ++ show a.functionsWithCrash
  , "}"
  ]

||| Generate test coverage with hits as JSON
public export
testCoverageToJson : TestCoverage -> String
testCoverageToJson sc =
  let pct = testCoveragePercent sc
  in unlines
    [ "{"
    , "  \"function\": \"" ++ sc.funcName ++ "\","
    , "  \"total_canonical\": " ++ show sc.totalCanonical ++ ","
    , "  \"total_impossible\": " ++ show sc.totalImpossible ++ ","
    , "  \"executed_canonical\": " ++ show sc.executedCanonical ++ ","
    , "  \"coverage_percent\": " ++ show pct
    , "}"
    ]

-- =============================================================================
-- High Impact Targets JSON Output
-- =============================================================================

||| Reading guide for LLM/tool consumption
public export
coverageReadingGuide : String
coverageReadingGuide = """
high_impact_targets: Functions with coverage issues, sorted by severity (highest first).
- kind: untested_canonical = has untested branches; bug_unhandled_input = partial code (CRASH); unknown_crash = investigate.
- branchCount: Total canonical branches in function (or bug/crash count).
- executedCount: Branches executed at runtime (from .ss.html profiler).
- severity: branchCount/executedCount ratio (2 decimal places). Inf = no branches executed or bug/unknown.
Action: Start fixing from the top of the list (highest severity) for maximum coverage improvement.
"""

||| Convert single HighImpactTarget to JSON object string
public export
targetToJson : HighImpactTarget -> String
targetToJson t = unlines
  [ "    {"
  , "      \"kind\": \"" ++ show t.kind ++ "\","
  , "      \"funcName\": \"" ++ t.funcName ++ "\","
  , "      \"moduleName\": \"" ++ t.moduleName ++ "\","
  , "      \"branchCount\": " ++ show t.branchCount ++ ","
  , "      \"executedCount\": " ++ show t.executedCount ++ ","
  , "      \"severity\": \"" ++ showSeverity t.severity ++ "\","
  , "      \"note\": \"" ++ t.note ++ "\""
  , "    }"
  ]

||| Convert list of targets to JSON array
public export
targetsToJsonArray : List HighImpactTarget -> String
targetsToJsonArray [] = "[]"
targetsToJsonArray targets =
  let items = map targetToJson targets
      joined = fastConcat $ intersperse ",\n" items
  in "[\n" ++ joined ++ "\n  ]"

||| Full coverage report with high impact targets as JSON
||| This is the canonical output format for both CLI and lazy core ask
public export
coverageReportToJson : TestAnalysis -> List HighImpactTarget -> String
coverageReportToJson analysis targets = unlines
  [ "{"
  , "  \"reading_guide\": \"" ++ escapeJson coverageReadingGuide ++ "\","
  , "  \"summary\": {"
  , "    \"total_functions\": " ++ show analysis.totalFunctions ++ ","
  , "    \"total_canonical\": " ++ show analysis.totalCanonical ++ ","
  , "    \"total_excluded\": " ++ show analysis.totalExcluded ++ ","
  , "    \"total_bugs\": " ++ show analysis.totalBugs ++ ","
  , "    \"total_optimizer_artifacts\": " ++ show analysis.totalOptimizerArtifacts ++ ","
  , "    \"total_unknown\": " ++ show analysis.totalUnknown ++ ","
  , "    \"total_compiler_generated\": " ++ show analysis.totalCompilerGenerated
  , "  },"
  , "  \"high_impact_targets\": " ++ targetsToJsonArray targets
  , "}"
  ]
  where
    escapeJson : String -> String
    escapeJson s = fastConcat $ map escapeChar (unpack s)
      where
        escapeChar : Char -> String
        escapeChar '\n' = "\\n"
        escapeChar '"'  = "\\\""
        escapeChar '\\' = "\\\\"
        escapeChar c    = singleton c

-- =============================================================================
-- OR Aggregation API (BranchId-based)
-- =============================================================================

||| Convert profiler covered count to TestRunHits
||| Note: This is a simplified mapping - full implementation would
||| correlate .ss.html line hits to specific BranchIds
convertToTestRunHits : String -> Nat -> List CompiledFunction -> TestRunHits
convertToTestRunHits testName coveredCount funcs =
  -- Generate BranchHits for the first N canonical branches
  -- This is an approximation until we have full line-to-branch mapping
  let allBranches = concatMap (.cases) funcs
      canonicalBranches = filter (\c => c.kind == Canonical) allBranches
      -- Mark first coveredCount branches as hit (approximation)
      hitBranches = take coveredCount canonicalBranches
      hits = map (\c => MkBranchHit c.branchId 1) hitBranches
  in MkTestRunHits testName "" hits

||| Analyze project with OR-aggregated coverage from multiple test modules
|||
||| This function:
||| 1. Gets static analysis from --dumpcases (with BranchIds)
||| 2. Runs all test modules with profiling
||| 3. OR-aggregates coverage across all test runs
|||
||| @ipkgPath    - Path to the .ipkg file
||| @testModules - List of test module names (each run separately for aggregation)
||| @returns     - Either error or AggregatedCoverage with OR-union of hits
public export
analyzeProjectWithAggregatedHits : (ipkgPath : String)
                                  -> (testModules : List String)
                                  -> IO (Either String AggregatedCoverage)
analyzeProjectWithAggregatedHits ipkgPath testModules = do
  let (projectDir, ipkgName) = splitIpkgPath ipkgPath

  -- Step 1: Get static analysis with BranchIds from --dumpcases
  dumpResult <- runDumpcasesDefault projectDir ipkgName
  case dumpResult of
    Left err => pure $ Left $ "Dumpcases failed: " ++ err
    Right dumpContent => do
      let funcs = parseDumpcasesFile dumpContent
      let staticAnalysis = toStaticBranchAnalysis funcs

      -- Step 2: Run tests with profiler
      testResult <- runTestsWithCoverage projectDir testModules 120
      case testResult of
        Left testErr => do
          -- Return static analysis only with 0 covered
          pure $ Right $ aggregateCoverage staticAnalysis []
        Right report => do
          -- Step 3: Convert profiler results to TestRunHits
          let coveredCount = report.branchCoverage.coveredBranches
          let runHits = convertToTestRunHits "all_tests" coveredCount funcs

          -- Step 4: Aggregate (single run for now, but architecture supports multiple)
          pure $ Right $ aggregateCoverage staticAnalysis [runHits]

||| Format AggregatedCoverage as text report
public export
formatAggregatedCoverage : AggregatedCoverage -> String
formatAggregatedCoverage ac =
  let pct = aggregatedCoveragePercent ac
  in unlines
    [ "=== Aggregated Coverage Report ==="
    , ""
    , "Test Runs: " ++ show (length ac.testRuns)
    , "Canonical Coverage: " ++ show ac.canonicalCovered
                            ++ "/" ++ show ac.canonicalTotal
                            ++ " (" ++ show (cast {to=Int} pct) ++ "%)"
    , "Bugs (UnhandledInput): " ++ show ac.bugsTotal
    , "Unknown CRASHes: " ++ show ac.unknownTotal
    , ""
    , "Coverage uses OR-semantics: branch is covered if hit by ANY test run"
    ]

||| AggregatedCoverage to JSON
public export
aggregatedCoverageToJson : AggregatedCoverage -> String
aggregatedCoverageToJson ac =
  let pct = aggregatedCoveragePercent ac
  in unlines
    [ "{"
    , "  \"test_runs\": " ++ show (length ac.testRuns) ++ ","
    , "  \"canonical_total\": " ++ show ac.canonicalTotal ++ ","
    , "  \"canonical_covered\": " ++ show ac.canonicalCovered ++ ","
    , "  \"coverage_percent\": " ++ show pct ++ ","
    , "  \"bugs_total\": " ++ show ac.bugsTotal ++ ","
    , "  \"unknown_total\": " ++ show ac.unknownTotal ++ ","
    , "  \"aggregation\": \"OR\""
    , "}"
    ]
