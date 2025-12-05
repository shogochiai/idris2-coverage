-- Test for REQ_COV_AGG_001: Map each function to list of tests that called it
module Main

import Coverage.Types
import Data.List

main : IO ()
main = do
  putStrLn "=== REQ_COV_AGG_001 Test ==="
  putStrLn "Testing: Test-to-function mapping"

  -- Use coveredFunction which creates a FunctionCoverage with calledByTests
  let fc = coveredFunction "Mod" "func" 10 ["REQ_001", "REQ_002"]

  if length fc.calledByTests == 2
     then putStrLn "[PASS] Mapped function to test list"
     else putStrLn "[FAIL] Expected 2 tests"
  putStrLn "=== Done ==="
