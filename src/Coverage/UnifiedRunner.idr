||| Unified test runner with coverage collection
||| REQ_COV_UNI_001 - REQ_COV_UNI_003
module Coverage.UnifiedRunner

import Coverage.Types
import Coverage.Collector
import System
import System.Clock
import System.File
import System.Directory
import Data.List
import Data.String

%default covering

-- =============================================================================
-- Temporary File Generation
-- =============================================================================

||| Generate unique identifier from timestamp
getUniqueId : IO String
getUniqueId = do
  t <- clockTime Monotonic
  pure $ "test_" ++ show (seconds t) ++ "_" ++ show (nanoseconds t `mod` 100000)

||| Join strings with separator
joinStrings : String -> List String -> String
joinStrings sep [] = ""
joinStrings sep [x] = x
joinStrings sep (x :: xs) = x ++ sep ++ joinStrings sep xs

||| Generate temporary test runner source code
||| The test modules must export a `runAllTests : IO ()` function
generateTempRunner : String -> List String -> String
generateTempRunner modName testModules = unlines
  [ "module " ++ modName
  , ""
  , unlines (map (\m => "import " ++ m) testModules)
  , ""
  , "main : IO ()"
  , "main = runAllTests"
  ]

||| Generate temporary .ipkg file
generateTempIpkg : String -> String -> List String -> String -> String
generateTempIpkg pkgName mainMod modules execName = unlines
  [ "package " ++ pkgName
  , "opts = \"--profile\""
  , "sourcedir = \"src\""
  , "main = " ++ mainMod
  , "executable = " ++ execName
  , "depends = base, contrib"
  , "modules = " ++ joinStrings ", " modules
  ]

-- =============================================================================
-- Test Output Parsing
-- =============================================================================

||| Safe tail of string - returns empty string if input is empty
safeTail : String -> String
safeTail s = if s == "" then "" else assert_total (strTail s)

||| Parse test output format: [PASS] TestName or [FAIL] TestName: message
covering
parseTestOutput : String -> List TestResult
parseTestOutput output =
  mapMaybe parseLine (lines output)
  where
    covering
    parseLine : String -> Maybe TestResult
    parseLine line =
      let trimmed = trim line
      in if isPrefixOf "[PASS]" trimmed
           then Just $ MkTestResult (trim $ substr 6 (length trimmed) trimmed) True Nothing
         else if isPrefixOf "[FAIL]" trimmed
           then
             let rest = trim $ substr 6 (length trimmed) trimmed
                 (name, msg) = break (== ':') rest
             in Just $ MkTestResult (trim name) False
                  (if msg == "" then Nothing else Just (trim $ safeTail msg))
         else Nothing

-- =============================================================================
-- File Cleanup
-- =============================================================================

||| Remove a file if it exists (ignore errors)
removeFileIfExists : String -> IO ()
removeFileIfExists path = do
  _ <- removeFile path
  pure ()

||| Clean up temporary files
cleanupTempFiles : String -> String -> String -> String -> IO ()
cleanupTempFiles tempIdr tempIpkg ssHtml profileHtml = do
  removeFileIfExists tempIdr
  removeFileIfExists tempIpkg
  removeFileIfExists ssHtml
  removeFileIfExists profileHtml

-- =============================================================================
-- Main Entry Point
-- =============================================================================

||| REQ_COV_UNI_001: Run tests with profiling and return combined report
||| REQ_COV_UNI_002: Clean up all temporary files
||| REQ_COV_UNI_003: Exclude test modules from coverage calculation
|||
||| @projectDir - Path to project root (containing .ipkg)
||| @testModules - List of test module names (e.g., ["Module.Tests.AllTests"])
||| @timeout - Max seconds for build+run (default 120)
export
runTestsWithCoverage : (projectDir : String)
                     -> (testModules : List String)
                     -> (timeout : Nat)
                     -> IO (Either String TestCoverageReport)
runTestsWithCoverage projectDir testModules timeout = do
  -- Validate inputs
  case testModules of
    [] => pure $ Left "No test modules specified"
    _ => do
      -- Generate unique names
      uid <- getUniqueId
      let tempModName = "TempTestRunner_" ++ uid
      let tempExecName = "temp-test-" ++ uid
      let tempIdrPath = projectDir ++ "/src/" ++ tempModName ++ ".idr"
      let tempIpkgPath = projectDir ++ "/" ++ tempExecName ++ ".ipkg"
      -- Chez Scheme profiler generates .ss.html in the current working directory (where executable runs)
      let ssHtmlPath = projectDir ++ "/" ++ tempExecName ++ ".ss.html"
      let profileHtmlPath = projectDir ++ "/profile.html"
      let execPath = projectDir ++ "/build/exec/" ++ tempExecName

      -- Generate temp runner source
      let runnerSource = generateTempRunner tempModName testModules
      Right () <- writeFile tempIdrPath runnerSource
        | Left err => pure $ Left $ "Failed to write temp runner: " ++ show err

      -- Generate temp .ipkg (include all Coverage modules + test modules)
      let allModules = tempModName :: testModules ++
            [ "Coverage.Types"
            , "Coverage.Collector"
            , "Coverage.SourceAnalyzer"
            , "Coverage.TestRunner"
            , "Coverage.Aggregator"
            , "Coverage.Report"
            , "Coverage.Linearity"
            , "Coverage.TypeAnalyzer"
            , "Coverage.StateSpace"
            , "Coverage.PathAnalysis"
            , "Coverage.Complexity"
            , "Coverage.TestHint"
            ]
      let ipkgContent = generateTempIpkg tempExecName tempModName allModules tempExecName
      Right () <- writeFile tempIpkgPath ipkgContent
        | Left err => do
            removeFileIfExists tempIdrPath
            pure $ Left $ "Failed to write temp ipkg: " ++ show err

      -- Build with profiling
      buildResult <- system $ "cd " ++ projectDir ++ " && idris2 --build " ++ tempExecName ++ ".ipkg 2>&1"
      if buildResult /= 0
        then do
          cleanupTempFiles tempIdrPath tempIpkgPath ssHtmlPath profileHtmlPath
          pure $ Left "Build failed"
        else do
          -- Run executable and capture output
          let runCmd = "cd " ++ projectDir ++ " && " ++ execPath ++ " 2>&1"
          runResult <- system runCmd
          -- Note: test failures shouldn't fail the whole run

          -- Read test output (need to capture it properly)
          -- For now, we'll read from a temp output file
          let outputFile = projectDir ++ "/temp_test_output_" ++ uid ++ ".txt"
          _ <- system $ "cd " ++ projectDir ++ " && " ++ execPath ++ " > " ++ outputFile ++ " 2>&1"

          Right testOutput <- readFile outputFile
            | Left _ => do
                cleanupTempFiles tempIdrPath tempIpkgPath ssHtmlPath profileHtmlPath
                pure $ Left "Failed to read test output"

          removeFileIfExists outputFile

          -- Parse test results
          let testResults = parseTestOutput testOutput
          let passedCount = length $ filter (.passed) testResults
          let failedCount = length $ filter (not . (.passed)) testResults

          -- Read and parse coverage data
          Right ssHtml <- readFile ssHtmlPath
            | Left _ => do
                cleanupTempFiles tempIdrPath tempIpkgPath ssHtmlPath profileHtmlPath
                -- Return results without coverage if .ss.html not found
                t <- clockTime UTC
                let timestamp = show (seconds t)
                let emptyBranch = MkBranchCoverageSummary 0 0 0 0.0 []
                pure $ Right $ MkTestCoverageReport testResults
                  (length testResults) passedCount failedCount emptyBranch timestamp

          -- Read Scheme source for function definitions
          let ssPath = projectDir ++ "/build/exec/" ++ tempExecName ++ "_app/" ++ tempExecName ++ ".ss"
          Right ssContent <- readFile ssPath
            | Left _ => do
                cleanupTempFiles tempIdrPath tempIpkgPath ssHtmlPath profileHtmlPath
                pure $ Left "Failed to read .ss file"

          -- Parse coverage (REQ_COV_UNI_003: exclude test modules)
          let funcDefs = parseSchemeDefs ssContent
          let branchPoints = parseBranchCoverage ssHtml
          let branchSummary = summarizeBranchCoverageExcludingTests funcDefs branchPoints

          -- Get timestamp
          t <- clockTime UTC
          let timestamp = show (seconds t)

          -- REQ_COV_UNI_002: Clean up
          cleanupTempFiles tempIdrPath tempIpkgPath ssHtmlPath profileHtmlPath

          pure $ Right $ MkTestCoverageReport
            testResults
            (length testResults)
            passedCount
            failedCount
            branchSummary
            timestamp
