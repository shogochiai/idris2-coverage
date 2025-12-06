||| Per-Module Test Runner for idris2-coverage
||| Based on lazy-idris Test.PerModule
module Test.PerModule

import System
import System.File
import Data.List
import Data.String

%default total

-- =============================================================================
-- Type Definitions
-- =============================================================================

||| Spec ID wrapper for type safety
public export
record SpecId where
  constructor MkSpecId
  value : String

public export
Show SpecId where
  show sid = sid.value

public export
Eq SpecId where
  (MkSpecId a) == (MkSpecId b) = a == b

||| Test definition: (SpecId, description, test function)
public export
TestDef : Type
TestDef = (SpecId, String, IO Bool)

||| Result of a single test execution
public export
record TestRunResult where
  constructor MkTestRunResult
  specId : SpecId
  description : String
  passed : Bool
  errorMsg : Maybe String

public export
Show TestRunResult where
  show r = "[" ++ (if r.passed then "PASS" else "FAIL") ++ "] " ++ show r.specId ++ ": " ++ r.description

-- =============================================================================
-- Test Execution
-- =============================================================================

||| Run a single test definition
export
covering
runSingleTest : TestDef -> IO TestRunResult
runSingleTest (sid, desc, testFn) = do
  result <- testFn
  pure $ MkTestRunResult sid desc result Nothing

||| Run all tests in a list and collect results
export
covering
runAllTests : List TestDef -> IO (List TestRunResult)
runAllTests = traverse runSingleTest

-- =============================================================================
-- Test Reporting
-- =============================================================================

||| Generate summary report
export
summarize : List TestRunResult -> String
summarize results =
  let totalCount = length results
      passedResults = filter (.passed) results
      passedCount = length passedResults
      failedCount = totalCount `minus` passedCount
      percentage = if totalCount > 0
                   then (cast passedCount * 100) `div` cast totalCount
                   else 0
  in unlines
    [ "Per-Module Test Summary:"
    , "  Total: " ++ show totalCount
    , "  Passed: " ++ show passedCount
    , "  Failed: " ++ show failedCount
    , "  Pass rate: " ++ show percentage ++ "%"
    ]

||| Print detailed results
export
covering
printResults : List TestRunResult -> IO ()
printResults results = do
  traverse_ printOne results
  putStrLn ""
  putStrLn $ summarize results
  where
    printOne : TestRunResult -> IO ()
    printOne r = putStrLn $ show r

-- =============================================================================
-- Test Runner Main
-- =============================================================================

||| Main test runner entry point for Per-Module tests
export
covering
runTestSuite : String -> List TestDef -> IO ()
runTestSuite suiteName tests = do
  putStrLn $ "Running " ++ suiteName ++ " (" ++ show (length tests) ++ " tests)..."
  results <- runAllTests tests
  printResults results
  let allPassed = all (.passed) results
  if allPassed
    then putStrLn "All tests passed!"
    else putStrLn "Some tests failed."

-- =============================================================================
-- Helper Constructors
-- =============================================================================

||| Create a test definition with spec ID string
export
test : String -> String -> IO Bool -> TestDef
test specId desc fn = (MkSpecId specId, desc, fn)

||| Create a pure test (no IO needed)
export
pureTest : String -> String -> Bool -> TestDef
pureTest specId desc result = (MkSpecId specId, desc, pure result)
