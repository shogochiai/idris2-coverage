-- Test for REQ_COV_REP_001: Generate JSON output matching lazy-idris schema
module Main

import Coverage.Types
import Coverage.Report
import Data.String

main : IO ()
main = do
  putStrLn "=== REQ_COV_REP_001 Test ==="
  putStrLn "Testing: JSON output generation"

  -- Create test data and generate JSON using actual module
  let fc = coveredFunction "TestMod" "testFunc" 10 ["REQ_TEST_001"]
  let json = functionCoverageJson fc

  -- Verify JSON contains required fields
  if isInfixOf "module" json && isInfixOf "name" json && isInfixOf "called_by_tests" json
     then putStrLn "[PASS] JSON contains required fields"
     else putStrLn "[FAIL] Missing required fields"
  putStrLn "=== Done ==="
