-- Test for REQ_COV_RUN_004: Associate profile results with test ID
module Main

import Coverage.Types

main : IO ()
main = do
  putStrLn "=== REQ_COV_RUN_004 Test ==="
  putStrLn "Testing: Test ID association"

  -- coveredFunction associates tests with coverage
  let fc = coveredFunction "Mod" "func" 10 ["REQ_RUN_004"]

  if "REQ_RUN_004" `elem` fc.calledByTests
     then putStrLn "[PASS] Test ID associated with profile"
     else putStrLn "[FAIL] Association failed"
  putStrLn "=== Done ==="
