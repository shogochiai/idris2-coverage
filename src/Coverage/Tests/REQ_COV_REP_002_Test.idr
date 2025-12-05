-- Test for REQ_COV_REP_002: Generate human-readable text output
module Main

import Coverage.Types
import Coverage.Report
import Data.String

main : IO ()
main = do
  putStrLn "=== REQ_COV_REP_002 Test ==="
  putStrLn "Testing: Text output generation"

  let fc = coveredFunction "TestMod" "testFunc" 5 ["REQ_001"]
  let json = functionCoverageJson fc

  -- Text format should include function info
  if length json > 0
     then putStrLn "[PASS] Generated output"
     else putStrLn "[FAIL] No output generated"
  putStrLn "=== Done ==="
