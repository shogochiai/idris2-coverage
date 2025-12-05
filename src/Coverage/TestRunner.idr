||| Test execution with profiling
||| REQ_COV_RUN_001 - REQ_COV_RUN_004
module Coverage.TestRunner

import Coverage.Types
import Coverage.Collector
import Data.List
import Data.List1
import Data.String
import System
import System.File
import System.Directory

%default total

-- =============================================================================
-- Test File Discovery
-- =============================================================================

||| REQ_COV_RUN_001: Discover test files matching glob pattern
||| Simple glob matching (supports * wildcard)
||| Simplified: checks if pattern parts are present in order
export
matchGlob : String -> String -> Bool
matchGlob pattern path =
  let parts = forget $ split (== '*') pattern
  in matchParts parts path
  where
    matchParts : List String -> String -> Bool
    matchParts [] _ = True
    matchParts [p] s = isSuffixOf p s || p == ""
    matchParts (p :: ps) s =
      if p == ""
         then matchParts ps s
         else if isPrefixOf p s
                 then matchParts ps (pack $ drop (length p) (unpack s))
                 else False

-- =============================================================================
-- Test Execution Result
-- =============================================================================

||| Result of running a single test with profiling
public export
record TestProfileResult where
  constructor MkTestProfileResult
  testId     : String           -- Test file path or ID
  testPassed : Bool
  profileHits : List ProfileHit

public export
Show TestProfileResult where
  show r = "TestResult(\{r.testId}, passed=\{show r.testPassed}, hits=\{show $ length r.profileHits})"

-- =============================================================================
-- Test Compilation
-- =============================================================================

||| REQ_COV_RUN_002: Compile test with idris2 --profile
export
covering
compileWithProfile : (testFile : String) -> (outputName : String) -> IO (Either String String)
compileWithProfile testFile outputName = do
  -- Build command: idris2 --profile -o <output> <testFile>
  let cmd = "idris2 --profile -o \{outputName} \{testFile} 2>&1"
  exitCode <- system cmd
  if exitCode == 0
     then pure $ Right outputName
     else pure $ Left "Compilation failed for \{testFile}"

-- =============================================================================
-- Test Execution
-- =============================================================================

||| REQ_COV_RUN_003: Execute compiled test and capture profile.html
export
covering
executeWithProfile : (execPath : String) -> (workDir : String) -> IO (Either String (Bool, String))
executeWithProfile execPath workDir = do
  -- Run the executable
  let cmd = "cd \{workDir} && ./build/exec/\{execPath} 2>&1"
  exitCode <- system cmd
  let testPassed = exitCode == 0
  -- Profile HTML should be in workDir
  let profilePath = workDir ++ "/profile.html"
  exists <- do
    Right _ <- readFile profilePath
      | Left _ => pure False
    pure True
  if exists
     then pure $ Right (testPassed, profilePath)
     else pure $ Left "profile.html not found after execution"

-- =============================================================================
-- Combined Test Run
-- =============================================================================

||| Run a single test with profiling and collect results
||| REQ_COV_RUN_004: Associate profile results with test ID
export
covering
runTestWithProfile : (testFile : String) -> (workDir : String) -> IO (Either String TestProfileResult)
runTestWithProfile testFile workDir = do
  -- Generate output name from test file
  let baseName = pack $ reverse $ takeWhile (/= '/') $ reverse $ unpack testFile
  let outputName = pack $ takeWhile (/= '.') $ unpack baseName

  -- Compile
  Right _ <- compileWithProfile testFile outputName
    | Left err => pure $ Left err

  -- Execute
  Right (passed, profilePath) <- executeWithProfile outputName workDir
    | Left err => pure $ Left err

  -- Collect profile data
  let schemePath = workDir ++ "/build/exec/" ++ outputName ++ "_app/" ++ outputName ++ ".ss"
  Right hits <- collectFromFiles profilePath schemePath
    | Left err => pure $ Left err

  pure $ Right $ MkTestProfileResult testFile passed hits

-- =============================================================================
-- Batch Test Execution
-- =============================================================================

||| Run multiple tests and collect all profile results
export
covering
runAllTests : (testFiles : List String) -> (workDir : String) -> IO (List (Either String TestProfileResult))
runAllTests testFiles workDir =
  traverse (\f => runTestWithProfile f workDir) testFiles

-- =============================================================================
-- Test File Listing
-- =============================================================================

||| List test files in a directory matching pattern
||| Note: This is a simplified implementation
export
covering
findTestFiles : (baseDir : String) -> (pattern : String) -> IO (List String)
findTestFiles baseDir pattern = do
  -- Use shell find command for simplicity
  let cmd = "find \{baseDir} -name '*.idr' -path '*/Tests/*' 2>/dev/null"
  -- This is simplified - in real impl would parse output
  pure []  -- Placeholder - real implementation needs shell execution
