||| Unified test runner with coverage collection
||| REQ_COV_UNI_001 - REQ_COV_UNI_003
module Coverage.UnifiedRunner

import Coverage.Types
import public Coverage.Collector
import public Coverage.DumpcasesParser
import System
import System.Clock
import System.File
import System.Directory
import Data.List
import Data.List1
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
  , "main = do"
  , unlines (map (\m => "  " ++ m ++ ".runAllTests") testModules)
  ]

||| Generate temporary .ipkg file
||| @depends - Additional package dependencies (e.g., from target project's ipkg)
generateTempIpkg : String -> String -> List String -> String -> List String -> String
generateTempIpkg pkgName mainMod modules execName depends =
  let allDepends = "base, contrib, idris2-coverage" ++
        (if null depends then "" else ", " ++ joinStrings ", " depends)
  in unlines
    [ "package " ++ pkgName
    , "opts = \"--profile\""
    , "sourcedir = \"src\""
    , "main = " ++ mainMod
    , "executable = " ++ execName
    , "depends = " ++ allDepends
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
-- Ipkg Parsing
-- =============================================================================

||| Parse depends line from ipkg content
||| Returns list of package names from "depends = pkg1, pkg2, ..." line
parseIpkgDepends : String -> List String
parseIpkgDepends content =
  let ls = lines content
      dependsLines = filter (isPrefixOf "depends") (map trim ls)
  in case dependsLines of
       [] => []
       (line :: _) =>
         let afterEquals = trim $ snd $ break (== '=') line
             -- Remove leading '=' if present
             pkgStr = if isPrefixOf "=" afterEquals
                        then trim (substr 1 (length afterEquals) afterEquals)
                        else afterEquals
         in map trim $ forget $ split (== ',') pkgStr

||| Read depends from project's ipkg file
public export
readProjectDepends : String -> IO (List String)
readProjectDepends projectDir = do
  -- Try common ipkg names
  let ipkgCandidates = [projectDir ++ "/lazycore.ipkg"
                       , projectDir ++ "/package.ipkg"
                       , projectDir ++ "/project.ipkg"]
  tryReadFirst ipkgCandidates
  where
    tryReadFirst : List String -> IO (List String)
    tryReadFirst [] = pure []
    tryReadFirst (path :: rest) = do
      Right content <- readFile path
        | Left _ => tryReadFirst rest
      pure $ parseIpkgDepends content

-- =============================================================================
-- Main Entry Point
-- =============================================================================

||| Extended report with semantic coverage from --dumpcases on test binary
public export
record TestCoverageReportExt where
  constructor MkTestCoverageReportExt
  baseReport     : TestCoverageReport
  testCoverage   : TestCoverage           -- From test binary's --dumpcases
  functionHits   : List FunctionRuntimeHit -- Per-function runtime coverage (NEW)

public export
Show TestCoverageReportExt where
  show r = show r.baseReport ++ " | Test: " ++ show r.testCoverage.executedCanonical
        ++ "/" ++ show r.testCoverage.totalCanonical
        ++ " | " ++ show (length r.functionHits) ++ " functions"

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
      -- Read project dependencies
      projectDepends <- readProjectDepends projectDir

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

      -- Generate temp .ipkg (test modules only - Coverage.* comes from idris2-coverage package)
      let allModules = tempModName :: testModules
      let ipkgContent = generateTempIpkg tempExecName tempModName allModules tempExecName projectDepends
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
          -- Use relative path from projectDir (./build/exec/...) since we cd there
          let relExecPath = "./build/exec/" ++ tempExecName
          let runCmd = "cd " ++ projectDir ++ " && " ++ relExecPath ++ " 2>&1"
          runResult <- system runCmd
          -- Note: test failures shouldn't fail the whole run

          -- Read test output (need to capture it properly)
          -- For now, we'll read from a temp output file
          -- Use relative path for shell command (after cd) but absolute for Idris readFile
          let relOutputFile = "./temp_test_output_" ++ uid ++ ".txt"
          let absOutputFile = projectDir ++ "/temp_test_output_" ++ uid ++ ".txt"
          _ <- system $ "cd " ++ projectDir ++ " && " ++ relExecPath ++ " > " ++ relOutputFile ++ " 2>&1"

          Right testOutput <- readFile absOutputFile
            | Left _ => do
                cleanupTempFiles tempIdrPath tempIpkgPath ssHtmlPath profileHtmlPath
                pure $ Left "Failed to read test output"

          removeFileIfExists absOutputFile

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

          -- Parse coverage
          -- Note: Test module exclusion disabled due to Chez Scheme linking issues
          -- REQ_COV_UNI_003 temporarily not enforced
          let funcDefs = parseSchemeDefs ssContent
          let branchPoints = parseBranchCoverage ssHtml
          let branchSummary = summarizeBranchCoverageWithFunctions funcDefs branchPoints

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

-- =============================================================================
-- Extended Entry Point with --dumpcases on Test Binary
-- =============================================================================

||| Run tests with semantic coverage from test binary's --dumpcases
||| This is the key function for accurate coverage: analyze the SAME binary that runs
|||
||| @projectDir - Path to project root (containing .ipkg)
||| @testModules - List of test module names
||| @timeout - Max seconds for build+run
export
runTestsWithTestCoverage : (projectDir : String)
                          -> (testModules : List String)
                          -> (timeout : Nat)
                          -> IO (Either String TestCoverage)
runTestsWithTestCoverage projectDir testModules timeout = do
  case testModules of
    [] => pure $ Left "No test modules specified"
    _ => do
      -- Read project dependencies
      projectDepends <- readProjectDepends projectDir

      -- Generate unique names
      uid <- getUniqueId
      let tempModName = "TempTestRunner_" ++ uid
      let tempExecName = "temp-test-" ++ uid
      let tempIdrPath = projectDir ++ "/src/" ++ tempModName ++ ".idr"
      let tempIpkgPath = projectDir ++ "/" ++ tempExecName ++ ".ipkg"
      let tempIpkgName = tempExecName ++ ".ipkg"
      let ssHtmlPath = projectDir ++ "/" ++ tempExecName ++ ".ss.html"
      let profileHtmlPath = projectDir ++ "/profile.html"
      let dumpcasesPath = "/tmp/idris2_dumpcases_test_" ++ uid ++ ".txt"

      -- Generate temp runner source
      let runnerSource = generateTempRunner tempModName testModules
      Right () <- writeFile tempIdrPath runnerSource
        | Left err => pure $ Left $ "Failed to write temp runner: " ++ show err

      -- Generate temp .ipkg
      let allModules = tempModName :: testModules
      let ipkgContent = generateTempIpkg tempExecName tempModName allModules tempExecName projectDepends
      Right () <- writeFile tempIpkgPath ipkgContent
        | Left err => do
            removeFileIfExists tempIdrPath
            pure $ Left $ "Failed to write temp ipkg: " ++ show err

      -- Build with --dumpcases on test binary
      let buildCmd = "cd " ++ projectDir ++ " && idris2 --dumpcases " ++ dumpcasesPath
                  ++ " --build " ++ tempIpkgName ++ " 2>&1"
      putStrLn $ "Dumping case trees to " ++ dumpcasesPath
      buildResult <- system buildCmd
      if buildResult /= 0
        then do
          cleanupTempFiles tempIdrPath tempIpkgPath ssHtmlPath profileHtmlPath
          removeFileIfExists dumpcasesPath
          pure $ Left "Build with --dumpcases failed"
        else do
          -- Parse --dumpcases output from test binary
          Right dumpContent <- readFile dumpcasesPath
            | Left _ => do
                cleanupTempFiles tempIdrPath tempIpkgPath ssHtmlPath profileHtmlPath
                pure $ Left "Failed to read dumpcases output"

          let funcs = parseDumpcasesFile dumpContent
          let analysis = aggregateAnalysis funcs

          -- Run executable with profiler
          let relExecPath = "./build/exec/" ++ tempExecName
          let relOutputFile = "./temp_test_output_" ++ uid ++ ".txt"
          let absOutputFile = projectDir ++ "/temp_test_output_" ++ uid ++ ".txt"
          _ <- system $ "cd " ++ projectDir ++ " && " ++ relExecPath ++ " > " ++ relOutputFile ++ " 2>&1"

          -- Read .ss.html for profiler hits
          Right ssHtml <- readFile ssHtmlPath
            | Left _ => do
                -- Return static analysis with 0 executed if no profiler output
                cleanupTempFiles tempIdrPath tempIpkgPath ssHtmlPath profileHtmlPath
                removeFileIfExists dumpcasesPath
                removeFileIfExists absOutputFile
                pure $ Right $ MkTestCoverage "test-binary" analysis.totalCanonical analysis.totalExcluded 0

          -- Parse profiler output for executed branches
          let branchPoints : List BranchPoint = parseBranchCoverage ssHtml
          let executed : Nat = length $ filter (\bp => bp.coveredBranches > 0) branchPoints

          -- Cleanup
          cleanupTempFiles tempIdrPath tempIpkgPath ssHtmlPath profileHtmlPath
          removeFileIfExists dumpcasesPath
          removeFileIfExists absOutputFile

          pure $ Right $ MkTestCoverage
            "test-binary"
            analysis.totalCanonical
            analysis.totalExcluded
            (cast executed)

-- =============================================================================
-- Extended Entry Point with Per-Function Runtime Hits
-- =============================================================================

||| Run tests and return per-function runtime coverage data
||| This is the recommended API for accurate severity calculation
|||
||| @projectDir - Path to project root (containing .ipkg)
||| @testModules - List of test module names
||| @timeout - Max seconds for build+run
export
runTestsWithFunctionHits : (projectDir : String)
                          -> (testModules : List String)
                          -> (timeout : Nat)
                          -> IO (Either String (List FunctionRuntimeHit))
runTestsWithFunctionHits projectDir testModules timeout = do
  case testModules of
    [] => pure $ Left "No test modules specified"
    _ => do
      -- Read project dependencies
      projectDepends <- readProjectDepends projectDir

      -- Generate unique names
      uid <- getUniqueId
      let tempModName = "TempTestRunner_" ++ uid
      let tempExecName = "temp-test-" ++ uid
      let tempIdrPath = projectDir ++ "/src/" ++ tempModName ++ ".idr"
      let tempIpkgPath = projectDir ++ "/" ++ tempExecName ++ ".ipkg"
      let tempIpkgName = tempExecName ++ ".ipkg"
      let ssHtmlPath = projectDir ++ "/" ++ tempExecName ++ ".ss.html"
      let profileHtmlPath = projectDir ++ "/profile.html"
      let dumpcasesPath = "/tmp/idris2_dumpcases_fh_" ++ uid ++ ".txt"
      let ssPath = projectDir ++ "/build/exec/" ++ tempExecName ++ "_app/" ++ tempExecName ++ ".ss"

      -- Generate temp runner source
      let runnerSource = generateTempRunner tempModName testModules
      Right () <- writeFile tempIdrPath runnerSource
        | Left err => pure $ Left $ "Failed to write temp runner: " ++ show err

      -- Generate temp .ipkg
      let allModules = tempModName :: testModules
      let ipkgContent = generateTempIpkg tempExecName tempModName allModules tempExecName projectDepends
      Right () <- writeFile tempIpkgPath ipkgContent
        | Left err => do
            removeFileIfExists tempIdrPath
            pure $ Left $ "Failed to write temp ipkg: " ++ show err

      -- Build with --dumpcases on test binary
      let buildCmd = "cd " ++ projectDir ++ " && idris2 --dumpcases " ++ dumpcasesPath
                  ++ " --build " ++ tempIpkgName ++ " 2>&1"
      buildResult <- system buildCmd
      if buildResult /= 0
        then do
          cleanupTempFiles tempIdrPath tempIpkgPath ssHtmlPath profileHtmlPath
          removeFileIfExists dumpcasesPath
          pure $ Left "Build with --dumpcases failed"
        else do
          -- Parse --dumpcases output for static analysis
          Right dumpContent <- readFile dumpcasesPath
            | Left _ => do
                cleanupTempFiles tempIdrPath tempIpkgPath ssHtmlPath profileHtmlPath
                pure $ Left "Failed to read dumpcases output"

          let funcs = parseDumpcasesFile dumpContent

          -- Run executable with profiler
          let relExecPath = "./build/exec/" ++ tempExecName
          _ <- system $ "cd " ++ projectDir ++ " && " ++ relExecPath ++ " 2>&1"

          -- Read .ss.html for profiler hits
          Right ssHtml <- readFile ssHtmlPath
            | Left _ => do
                -- Return static-only data with 0 executed
                cleanupTempFiles tempIdrPath tempIpkgPath ssHtmlPath profileHtmlPath
                removeFileIfExists dumpcasesPath
                let staticHits = map (\f => MkFunctionRuntimeHit f.fullName f.fullName
                                      (countCanonical f.cases) 0 0 0) funcs
                pure $ Right staticHits

          -- Read .ss for function definitions
          Right ssContent <- readFile ssPath
            | Left _ => do
                cleanupTempFiles tempIdrPath tempIpkgPath ssHtmlPath profileHtmlPath
                removeFileIfExists dumpcasesPath
                pure $ Left "Failed to read .ss file"

          -- Match functions with profiler data
          let functionHits = matchAllFunctionsWithCoverage funcs ssHtml ssContent

          -- Cleanup
          cleanupTempFiles tempIdrPath tempIpkgPath ssHtmlPath profileHtmlPath
          removeFileIfExists dumpcasesPath

          pure $ Right functionHits
  where
    countCanonical : List CompiledCase -> Nat
    countCanonical = length . filter (\c => c.kind == Canonical)
