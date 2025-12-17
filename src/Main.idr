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

import Data.List
import Data.String
import System
import System.File

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
idris2-coverage - Code coverage tool for Idris2

USAGE:
  idris2-cov [OPTIONS] <ipkg>
  idris2-cov branches [--uncovered] <ipkg>
  idris2-cov --run-tests "pattern" --output coverage.json <ipkg>

COMMANDS:
  branches              Show branch analysis from --dumpcases
    --uncovered         Only show functions with uncovered branches (bugs)

OPTIONS:
  -h, --help              Show this help message
  -v, --version           Show version
  -f, --format <fmt>      Output format: json (default) or text
  -o, --output <path>     Output file path (stdout if not specified)
  --run-tests <pattern>   Run tests matching glob pattern and collect coverage

EXAMPLES:
  # Show all branches
  idris2-cov branches myproject.ipkg

  # Show only uncovered branches (UnhandledInput, Unknown CRASH)
  idris2-cov branches --uncovered myproject.ipkg

  # Generate coverage report from existing profile data
  idris2-cov --format json --output coverage.json myproject.ipkg

  # Run tests and generate coverage
  idris2-cov --run-tests "src/*/Tests/*_Test.idr" -o coverage.json myproject.ipkg

OUTPUT FORMAT:
  JSON output follows lazy-idris coverage schema with:
  - functions: List of function coverage with called_by_tests
  - modules: Module-level summary
  - project: Project-level summary
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
-- Demo Report Generation
-- =============================================================================

||| Generate a demo report for testing
demoReport : CoverageReport
demoReport =
  let funcs = [ MkFunctionCoverage "Sample" "add" (Just "Int -> Int -> Int")
                  (Just 5) (Just 6) 2 2 100.0 ["test_add"]
              , MkFunctionCoverage "Sample" "multiply" (Just "Int -> Int -> Int")
                  (Just 9) (Just 10) 2 2 100.0 ["test_multiply"]
              , MkFunctionCoverage "Sample" "factorial" (Just "Int -> Int")
                  (Just 13) (Just 15) 3 3 100.0 ["test_factorial"]
              , MkFunctionCoverage "Sample" "unused" (Just "Int -> Int")
                  (Just 18) (Just 19) 0 2 0.0 []
              ]
      mods = [ MkModuleCoverage "src/Sample.idr" 4 3 75.0 ]
      proj = MkProjectCoverage 4 3 75.0 Nothing
  in MkCoverageReport funcs mods proj

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
               _ => do
                 -- For now, generate a demo report
                 -- Real implementation would:
                 -- 1. Parse ipkg
                 -- 2. Run tests with --profile
                 -- 3. Collect profile data
                 -- 4. Analyze sources
                 -- 5. Aggregate coverage
                 let report = demoReport

                 case opts.outputPath of
                   Nothing => printReport opts.format report
                   Just path => do
                     Right () <- writeReport opts.format report path
                       | Left err => putStrLn $ "Error: " ++ err
                     putStrLn $ "Coverage report written to " ++ path
