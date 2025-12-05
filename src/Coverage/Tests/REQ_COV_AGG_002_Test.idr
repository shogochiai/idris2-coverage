-- Test for REQ_COV_AGG_002: Compute coverage_percent per function
module Main

import Coverage.Types

main : IO ()
main = do
  putStrLn "=== REQ_COV_AGG_002 Test ==="
  putStrLn "Testing: Coverage percent computation"

  let fc = coveredFunction "Mod" "func" 10 ["t1"]

  putStrLn $ "Coverage percent: " ++ show fc.coveragePercent
  if fc.coveragePercent == 100.0
     then putStrLn "[PASS] Computed 100% coverage"
     else putStrLn "[FAIL] Expected 100%"
  putStrLn "=== Done ==="
