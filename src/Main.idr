||| idris2-coverage CLI
||| Code coverage tool for Idris2 using Chez Scheme profiler
module Main

import Coverage.Types
import Coverage.Collector
import Coverage.SourceAnalyzer
import Coverage.TestRunner
import Coverage.Aggregator
import Coverage.Report
import Coverage.DumpcasesParser
import Coverage.SemanticCoverage
import Coverage.UnifiedRunner

import Data.List
import Data.List1
import Data.String
import Data.String.Extra
import System
import System.File
import System.Directory

%default covering

-- =============================================================================
-- CLI Options
-- =============================================================================

record Options where
  constructor MkOptions
  format       : OutputFormat
  outputPath   : Maybe String
  runTests     : Maybe String    -- glob pattern for tests
  ipkgPath     : Maybe String
  sourceFiles  : List String
  showHelp     : Bool
  showVersion  : Bool
  subcommand   : Maybe String    -- "branches" etc.
  showUncovered : Bool           -- --uncovered flag for branches

defaultOptions : Options
defaultOptions = MkOptions JSON Nothing Nothing Nothing [] False False Nothing False

-- =============================================================================
-- Argument Parsing
-- =============================================================================

parseArgs : List String -> Options -> Options
parseArgs [] opts = opts
parseArgs ("branches" :: rest) opts =
  parseArgs rest ({ subcommand := Just "branches" } opts)
parseArgs ("--uncovered" :: rest) opts =
  parseArgs rest ({ showUncovered := True } opts)
parseArgs ("--help" :: rest) opts =
  parseArgs rest ({ showHelp := True } opts)
parseArgs ("-h" :: rest) opts =
  parseArgs rest ({ showHelp := True } opts)
parseArgs ("--version" :: rest) opts =
  parseArgs rest ({ showVersion := True } opts)
parseArgs ("-v" :: rest) opts =
  parseArgs rest ({ showVersion := True } opts)
parseArgs ("--format" :: fmt :: rest) opts =
  let format = if fmt == "text" then Text else JSON
  in parseArgs rest ({ format := format } opts)
parseArgs ("-f" :: fmt :: rest) opts =
  let format = if fmt == "text" then Text else JSON
  in parseArgs rest ({ format := format } opts)
parseArgs ("--output" :: path :: rest) opts =
  parseArgs rest ({ outputPath := Just path } opts)
parseArgs ("-o" :: path :: rest) opts =
  parseArgs rest ({ outputPath := Just path } opts)
parseArgs ("--run-tests" :: pattern :: rest) opts =
  parseArgs rest ({ runTests := Just pattern } opts)
parseArgs (arg :: rest) opts =
  if isSuffixOf ".ipkg" arg
     then parseArgs rest ({ ipkgPath := Just arg } opts)
     else if isSuffixOf ".idr" arg
             then parseArgs rest ({ sourceFiles $= (arg ::) } opts)
             else parseArgs rest opts

-- =============================================================================
-- Help Text
-- =============================================================================

helpText : String
helpText = """
idris2-coverage - Semantic coverage for Idris2 (absurd-pattern-omitting)

USAGE:
  idris2-cov <ipkg>                        Run tests & show coverage
  idris2-cov branches [--uncovered] <ipkg> Static branch analysis

EXAMPLES:
  # Run all tests, report semantic coverage
  idris2-cov myproject.ipkg

  # Static analysis only (no test execution)
  idris2-cov branches myproject.ipkg
  idris2-cov branches --uncovered myproject.ipkg

OPTIONS:
  -h, --help      Show this help message
  -v, --version   Show version

WHAT IT DOES:
  1. Discovers test modules (modules with 'Test' in name)
  2. Runs tests with Chez Scheme profiler
  3. Analyzes --dumpcases output for canonical branches
  4. Excludes absurd patterns (void, impossible cases)
  5. Reports: covered/canonical branches per module
  6. Shows uncovered branches as test targets
"""

versionText : String
versionText = "idris2-coverage 0.1.0"

-- =============================================================================
-- Branches Command
-- =============================================================================

||| Check if function has uncovered branches (bugs or unknown)
hasUncoveredBranches : CompiledFunction -> Bool
hasUncoveredBranches f =
  countBugCases f > 0 || countUnknownCases f > 0

||| Format a single function's branch info
formatFunctionBranches : CompiledFunction -> String
formatFunctionBranches f =
  let canonical = countCanonicalCases f
      bugs = countBugCases f
      excluded = countExcludedCases f
      optimizer = countOptimizerArtifacts f
      unknown = countUnknownCases f
      status = if bugs > 0 || unknown > 0 then "[UNCOVERED]" else "[OK]"
  in status ++ " " ++ f.fullName ++ ": "
     ++ show canonical ++ " canonical"
     ++ (if bugs > 0 then ", " ++ show bugs ++ " bugs" else "")
     ++ (if unknown > 0 then ", " ++ show unknown ++ " unknown" else "")
     ++ (if excluded > 0 then ", " ++ show excluded ++ " excluded" else "")
     ++ (if optimizer > 0 then ", " ++ show optimizer ++ " optimizer-artifacts" else "")

||| Run branches subcommand
runBranches : Options -> IO ()
runBranches opts = do
  case opts.ipkgPath of
    Nothing => putStrLn "Error: No .ipkg file specified"
    Just ipkg => do
      result <- analyzeProjectFunctions ipkg
      case result of
        Left err => putStrLn $ "Error: " ++ err
        Right funcs => do
          let filtered = if opts.showUncovered
                         then filter hasUncoveredBranches funcs
                         else funcs
          let analysis = aggregateAnalysis funcs

          -- Header
          putStrLn "=== Branch Analysis ==="
          putStrLn ""

          -- Summary
          putStrLn $ "Functions: " ++ show analysis.totalFunctions
          putStrLn $ "Canonical branches: " ++ show analysis.totalCanonical
          putStrLn $ "Uncovered (bugs): " ++ show analysis.totalBugs
          putStrLn $ "Unknown CRASHes: " ++ show analysis.totalUnknown
          putStrLn $ "Excluded (void): " ++ show analysis.totalExcluded
          putStrLn $ "Optimizer artifacts: " ++ show analysis.totalOptimizerArtifacts
          putStrLn ""

          -- Function list
          if opts.showUncovered
             then putStrLn $ "Functions with uncovered branches (" ++ show (length filtered) ++ "):"
             else putStrLn "All functions:"
          putStrLn ""

          traverse_ (putStrLn . formatFunctionBranches) filtered

-- =============================================================================
-- Main Coverage Command
-- =============================================================================

||| Split ipkg path into directory and filename
splitPath : String -> (String, String)
splitPath path =
  let parts = forget $ split (== '/') path
  in case parts of
       [] => (".", path)
       [x] => (".", x)
       _ => let revParts = reverse parts
            in case revParts of
                 [] => (".", path)
                 (file :: dirs) => (fastConcat $ intersperse "/" (reverse dirs), file)

||| Parse ipkg to extract test module names (modules containing "Test" or in Tests/)
||| Returns list of module names that look like test modules
parseTestModulesFromIpkg : String -> List String
parseTestModulesFromIpkg content =
  let ls = lines content
      moduleLine = find (isInfixOf "modules") ls
  in case moduleLine of
       Nothing => []
       Just line =>
         let afterEq = snd $ break (== '=') (unpack line)
             moduleStr = pack $ drop 1 afterEq  -- drop '='
             modules = map trim $ forget $ split (== ',') moduleStr
         in filter isTestModule modules
  where
    isTestModule : String -> Bool
    isTestModule m = isInfixOf "Test" m || isInfixOf "Tests" m

||| Group functions by module name
groupByModule : List CompiledFunction -> List (String, List CompiledFunction)
groupByModule funcs =
  let modules = nub $ map (.moduleName) funcs
  in map (\m => (m, filter (\f => f.moduleName == m) funcs)) modules

||| Format module coverage line
formatModuleLine : String -> Nat -> Nat -> String
formatModuleLine modName covCount totCount =
  let pct : Integer = if totCount == 0 then 100 else (cast covCount * 100) `div` cast totCount
      padding = pack $ replicate (max 0 (30 `minus` length modName)) ' '
  in "  " ++ modName ++ padding ++ show covCount ++ "/" ++ show totCount
     ++ "  (" ++ show pct ++ "%)"

||| Run main coverage analysis
runCoverage : Options -> IO ()
runCoverage opts = do
  case opts.ipkgPath of
    Nothing => putStrLn "Error: No .ipkg file specified\n\nUsage: idris2-cov <project.ipkg>"
    Just ipkg => do
      let (projectDir, ipkgName) = splitPath ipkg

      putStrLn "=== Semantic Coverage ==="
      putStrLn ""
      putStrLn $ "Analyzing: " ++ ipkg
      putStrLn ""

      -- Step 1: Get canonical branches from dumpcases (static analysis)
      putStrLn "Running static analysis (dumpcases)..."
      staticResult <- analyzeProjectFunctions ipkg
      case staticResult of
        Left err => putStrLn $ "Error in static analysis: " ++ err
        Right funcs => do
          let analysis = aggregateAnalysis funcs

          -- Step 2: Try to find and run tests
          putStrLn "Looking for test modules..."
          Right ipkgContent <- readFile ipkg
            | Left _ => do
                putStrLn "Warning: Could not read ipkg file"
                showStaticOnly analysis funcs

          let testModules = parseTestModulesFromIpkg ipkgContent

          case testModules of
            [] => do
              putStrLn "No test modules found (modules with 'Test' in name)"
              putStrLn ""
              showStaticOnly analysis funcs
            mods => do
              putStrLn $ "Found test modules: " ++ show mods
              putStrLn "Running tests with profiler..."
              putStrLn ""

              -- Run tests and collect coverage
              testResult <- runTestsWithCoverage projectDir mods 300
              case testResult of
                Left err => do
                  putStrLn $ "Warning: Test run failed: " ++ err
                  putStrLn "Showing static analysis only."
                  putStrLn ""
                  showStaticOnly analysis funcs
                Right report => do
                  showCoverageReport analysis funcs report
  where
    printModuleStatic : (String, List CompiledFunction) -> IO ()
    printModuleStatic p =
      let m = fst p
          fs = snd p
          tot = sum $ map countCanonicalCases fs
      in putStrLn $ formatModuleLine m 0 tot

    showStaticOnly : SemanticAnalysis -> List CompiledFunction -> IO ()
    showStaticOnly analysis funcs = do
      putStrLn "Static Analysis (no runtime data):"
      putStrLn $ "  Canonical branches: " ++ show analysis.totalCanonical
      putStrLn $ "  Excluded (absurd):  " ++ show analysis.totalExcluded
      putStrLn ""
      putStrLn "By Module:"
      let grouped = groupByModule funcs
      traverse_ printModuleStatic grouped

    printModuleCov : Nat -> Nat -> (String, List CompiledFunction) -> IO ()
    printModuleCov cov tot p =
      let m = fst p
          fs = snd p
          modTot = sum $ map countCanonicalCases fs
          modCov : Nat = cast $ (cast modTot * cast cov) `div` cast (max 1 tot)
      in putStrLn $ formatModuleLine m modCov modTot

    printUncovered : (String, BranchPoint) -> IO ()
    printUncovered p = putStrLn $ "  " ++ fst p ++ ": line " ++ show (snd p).line

    showCoverageReport : SemanticAnalysis -> List CompiledFunction -> TestCoverageReport -> IO ()
    showCoverageReport analysis funcs report = do
      let covered = report.branchCoverage.coveredBranches
      let tot = analysis.totalCanonical
      let pct : Integer = if tot == 0 then 100 else (cast covered * 100) `div` cast tot

      putStrLn $ "Coverage: " ++ show covered ++ "/" ++ show tot
               ++ " canonical branches (" ++ show pct ++ "%)"
      putStrLn ""

      -- Test results summary
      putStrLn $ "Tests: " ++ show report.passedTests ++ " passed, "
               ++ show report.failedTests ++ " failed"
      putStrLn ""

      -- By module breakdown
      putStrLn "By Module:"
      let grouped = groupByModule funcs
      traverse_ (printModuleCov covered tot) grouped
      putStrLn ""

      -- Show uncovered branches (test targets)
      let uncoveredBranches = report.branchCoverage.uncoveredBranches
      case uncoveredBranches of
        [] => putStrLn "All branches covered!"
        _ => do
          putStrLn $ "Uncovered (test targets): " ++ show (length uncoveredBranches) ++ " branches"
          traverse_ printUncovered (take 10 uncoveredBranches)
          when (length uncoveredBranches > 10) $
            putStrLn $ "  ... and " ++ show (length uncoveredBranches `minus` 10) ++ " more"

-- =============================================================================
-- Main
-- =============================================================================

main : IO ()
main = do
  args <- getArgs
  let opts = parseArgs (drop 1 args) defaultOptions  -- drop program name

  if opts.showHelp
     then putStrLn helpText
     else if opts.showVersion
             then putStrLn versionText
             else case opts.subcommand of
               Just "branches" => runBranches opts
               _ => runCoverage opts
