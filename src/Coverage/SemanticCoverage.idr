||| High-level Semantic Coverage API
|||
||| This module provides a simple interface for analyzing Idris2 projects:
|||
|||   analyzeProject : String -> IO (Either String SemanticAnalysis)
|||   analyzeProjectWithHits : String -> List String -> IO (Either String SemanticCoverage)
|||
||| The API handles --dumpcases invocation internally, so users don't need to
||| know the non-obvious syntax: idris2 --dumpcases <output> --build <package.ipkg>
|||
||| Issue #5 & #6: This is the recommended entry point for idris2-coverage users.
module Coverage.SemanticCoverage

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
||| 3. Returns SemanticAnalysis with the breakdown
|||
||| @ipkgPath - Path to the .ipkg file (e.g., "myproject.ipkg" or "path/to/project/project.ipkg")
||| @returns  - Either error message or SemanticAnalysis
public export
analyzeProject : (ipkgPath : String) -> IO (Either String SemanticAnalysis)
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
||| @returns     - Either error or SemanticCoverage with executed counts
public export
analyzeProjectWithHits : (ipkgPath : String)
                       -> (testModules : List String)
                       -> IO (Either String SemanticCoverage)
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
          pure $ Right $ MkSemanticCoverage
            "project"
            analysis.totalCanonical
            analysis.totalImpossible
            0
        Right report => do
          -- Step 3: Extract executed count from profiler
          -- Use coveredBranches as approximation for executed canonical cases
          let executed = report.branchCoverage.coveredBranches
          pure $ Right $ MkSemanticCoverage
            "project"
            analysis.totalCanonical
            analysis.totalImpossible
            executed

-- =============================================================================
-- Per-Function Analysis with Runtime Hits
-- =============================================================================

||| Detailed per-function semantic coverage with runtime hits
public export
record FunctionSemanticCoverage where
  constructor MkFunctionSemanticCoverage
  funcName          : String
  moduleName        : String
  totalCanonical    : Nat
  totalImpossible   : Nat
  executedCanonical : Nat
  coveragePercent   : Double

public export
Show FunctionSemanticCoverage where
  show fsc = fsc.funcName ++ ": " ++ show fsc.executedCanonical
          ++ "/" ++ show fsc.totalCanonical
          ++ " (" ++ show (cast {to=Int} fsc.coveragePercent) ++ "%)"

isImpossibleCaseSC : CompiledCase -> Bool
isImpossibleCaseSC c = case c.kind of
  NonCanonical CrashImpossible => True
  NonCanonical CrashNoClauses  => True
  _ => False

countCanonicalCasesSC : CompiledFunction -> Nat
countCanonicalCasesSC func = length $ filter (\c => c.kind == Canonical) func.cases

countImpossibleCasesSC : CompiledFunction -> Nat
countImpossibleCasesSC func = length $ filter isImpossibleCaseSC func.cases

||| Convert CompiledFunction to FunctionSemanticCoverage with hits
functionToSemanticCoverage : CompiledFunction -> Nat -> FunctionSemanticCoverage
functionToSemanticCoverage f executed =
  let canonical = countCanonicalCasesSC f in
  let impossibleCount = countImpossibleCasesSC f in
  let pct = if canonical == 0
            then 100.0
            else cast executed / cast canonical * 100.0
  in MkFunctionSemanticCoverage
       f.fullName
       f.moduleName
       canonical
       impossibleCount
       executed
       pct

-- =============================================================================
-- Report Generation
-- =============================================================================

||| Generate semantic coverage summary as text
public export
formatSemanticAnalysis : SemanticAnalysis -> String
formatSemanticAnalysis a = unlines
  [ "=== Semantic Coverage Report ==="
  , ""
  , "Project Summary:"
  , "  Functions analyzed: " ++ show a.totalFunctions
  , "  Canonical cases: " ++ show a.totalCanonical
  , "  Impossible cases (excluded): " ++ show a.totalImpossible
  , "  Not-covered cases (bugs): " ++ show a.totalNotCovered
  , "  Functions with CRASH: " ++ show a.functionsWithCrash
  ]

||| Generate semantic coverage with hits as text
public export
formatSemanticCoverage : SemanticCoverage -> String
formatSemanticCoverage sc =
  let pct = semanticCoveragePercent sc
  in unlines
    [ "=== Semantic Coverage Report ==="
    , ""
    , "Coverage: " ++ show sc.executedCanonical
               ++ "/" ++ show sc.totalCanonical
               ++ " (" ++ show (cast {to=Int} pct) ++ "%)"
    , "Impossible cases (excluded): " ++ show sc.totalImpossible
    ]

-- =============================================================================
-- JSON Output
-- =============================================================================

||| Generate semantic analysis as JSON
public export
semanticAnalysisToJson : SemanticAnalysis -> String
semanticAnalysisToJson a = unlines
  [ "{"
  , "  \"total_functions\": " ++ show a.totalFunctions ++ ","
  , "  \"total_canonical\": " ++ show a.totalCanonical ++ ","
  , "  \"total_impossible\": " ++ show a.totalImpossible ++ ","
  , "  \"total_not_covered\": " ++ show a.totalNotCovered ++ ","
  , "  \"functions_with_crash\": " ++ show a.functionsWithCrash
  , "}"
  ]

||| Generate semantic coverage with hits as JSON
public export
semanticCoverageToJson : SemanticCoverage -> String
semanticCoverageToJson sc =
  let pct = semanticCoveragePercent sc
  in unlines
    [ "{"
    , "  \"function\": \"" ++ sc.funcName ++ "\","
    , "  \"total_canonical\": " ++ show sc.totalCanonical ++ ","
    , "  \"total_impossible\": " ++ show sc.totalImpossible ++ ","
    , "  \"executed_canonical\": " ++ show sc.executedCanonical ++ ","
    , "  \"coverage_percent\": " ++ show pct
    , "}"
    ]
