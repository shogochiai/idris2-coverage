-- Test for REQ_COV_AGG_003: Detect dead code (exported but not in .ss)
module Main

import Coverage.Types

main : IO ()
main = do
  putStrLn "=== REQ_COV_AGG_003 Test ==="
  putStrLn "Testing: Dead code detection"

  -- uncoveredFunction creates 0% coverage = potential dead code
  let fc = uncoveredFunction "Mod" "deadFunc"

  if fc.coveragePercent == 0.0
     then putStrLn "[PASS] Detected uncovered function"
     else putStrLn "[FAIL] Expected 0%"
  putStrLn "=== Done ==="
