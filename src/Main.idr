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
import System.Clock

%default covering

-- =============================================================================
-- CLI Options
-- =============================================================================

record Options where
  constructor MkOptions
  format       : OutputFormat
  outputPath   : Maybe String
  runTests     : Maybe String    -- glob pattern for tests
  targetPath   : Maybe String    -- directory or ipkg path
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
  -- Accept directory or ipkg as target
  if isSuffixOf ".idr" arg
     then parseArgs rest ({ sourceFiles $= (arg ::) } opts)
     else parseArgs rest ({ targetPath := Just arg } opts)

-- =============================================================================
-- Help Text
-- =============================================================================

helpText : String
helpText = """
idris2-coverage - Classification-aware semantic coverage for Idris2

USAGE:
  idris2-cov branches [--uncovered] <dir>   Static branch analysis
  idris2-cov branches [--uncovered] <ipkg>  Static branch analysis

EXAMPLES:
  # Analyze directory (finds .ipkg automatically)
  idris2-cov branches pkgs/LazyCore/

  # Show only functions with coverage gaps
  idris2-cov branches --uncovered pkgs/LazyCore/

OPTIONS:
  -h, --help        Show this help message
  -v, --version     Show version
  --uncovered       Only show functions with bugs/unknown CRASHes

BRANCH CLASSIFICATION (per dunham):
  canonical:    Reachable branches (test denominator)
  excluded:     NoClauses - void/uninhabited (safe to exclude)
  bugs:         UnhandledInput - genuine coverage gaps (FIX THESE)
  optimizer:    Nat case - non-semantic artifact (ignore)
  unknown:      Other CRASHes - conservative bucket (investigate)
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

||| Find .ipkg file in directory
findIpkgInDir : String -> IO (Maybe String)
findIpkgInDir dir = do
  Right entries <- listDir dir
    | Left _ => pure Nothing
  let ipkgs = filter (isSuffixOf ".ipkg") entries
  case ipkgs of
    [] => pure Nothing
    (x :: _) => pure $ Just (dir ++ "/" ++ x)

||| Resolve target path to ipkg path
resolveIpkg : String -> IO (Either String String)
resolveIpkg target = do
  if isSuffixOf ".ipkg" target
     then pure $ Right target
     else do
       -- Assume it's a directory, look for .ipkg
       result <- findIpkgInDir target
       case result of
         Nothing => pure $ Left $ "No .ipkg file found in " ++ target
         Just ipkg => pure $ Right ipkg

||| Get current timestamp as ISO-ish string
getTimestamp : IO String
getTimestamp = do
  t <- clockTime UTC
  let secs = seconds t
  pure $ "timestamp:" ++ show secs

||| Format bug function line for report
formatBugLine : CompiledFunction -> String
formatBugLine f = "- " ++ f.fullName ++ ": UnhandledInput"

||| Format unknown function line for report
formatUnknownLine : CompiledFunction -> String
formatUnknownLine f = "- " ++ f.fullName ++ ": Unknown CRASH"

||| Run branches subcommand with classification-aware report
runBranches : Options -> IO ()
runBranches opts = do
  case opts.targetPath of
    Nothing => putStrLn "Error: No target specified\n\nUsage: idris2-cov branches <dir-or-ipkg>"
    Just target => do
      ipkgResult <- resolveIpkg target
      case ipkgResult of
        Left err => putStrLn $ "Error: " ++ err
        Right ipkg => do
          result <- analyzeProjectFunctions ipkg
          case result of
            Left err => putStrLn $ "Error: " ++ err
            Right funcs => do
              let analysis = aggregateAnalysis funcs
              let bugFuncs = filter (\f => countBugCases f > 0) funcs
              let unknownFuncs = filter (\f => countUnknownCases f > 0) funcs

              -- Get timestamp
              ts <- getTimestamp

              -- Classification-aware report format
              putStrLn $ "# Coverage Report"
              putStrLn $ ts
              putStrLn $ "target: " ++ target
              putStrLn ""
              putStrLn "## Branch Classification"
              putStrLn $ "canonical:          " ++ show analysis.totalCanonical
                       ++ "   # reachable branches (test denominator)"
              putStrLn $ "excluded_void:      " ++ show analysis.totalExcluded
                       ++ "   # NoClauses - safe to exclude"
              putStrLn $ "bugs:               " ++ show analysis.totalBugs
                       ++ "   # UnhandledInput - genuine gaps (FIX THESE)"
              putStrLn $ "optimizer_artifacts:" ++ show analysis.totalOptimizerArtifacts
                       ++ "   # Nat case - ignore (non-semantic)"
              putStrLn $ "unknown:            " ++ show analysis.totalUnknown
                       ++ "   # conservative bucket"
              putStrLn ""

              -- Show bugs (UnhandledInput) - the main test targets
              case bugFuncs of
                [] => putStrLn "## Bugs (UnhandledInput): none"
                _ => do
                  putStrLn $ "## Bugs (UnhandledInput) - Test Targets: " ++ show (length bugFuncs)
                  traverse_ (putStrLn . formatBugLine) bugFuncs
              putStrLn ""

              -- Show unknown CRASHes
              case unknownFuncs of
                [] => putStrLn "## Unknown CRASHes: none"
                _ => do
                  putStrLn $ "## Unknown CRASHes (investigate): " ++ show (length unknownFuncs)
                  traverse_ (putStrLn . formatUnknownLine) unknownFuncs

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
             else runBranches opts  -- branches is the default (and only) command
