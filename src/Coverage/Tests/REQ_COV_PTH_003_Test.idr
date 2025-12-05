-- Test for REQ_COV_PTH_003: Analyze Either parameter paths
module Main

import Coverage.PathAnalysis
import Coverage.Types
import Data.List

main : IO ()
main = do
  putStrLn "=== REQ_COV_PTH_003 Test ==="
  putStrLn "Testing: Analyze Either parameter paths"
  putStrLn ""

  -- Analyze Either parameter
  let eitherAnalysis = analyzeEitherPaths "result"

  putStrLn $ "Parameter: " ++ eitherAnalysis.paramName
  putStrLn $ "Left branch pattern: " ++ eitherAnalysis.leftBranch.pattern
  putStrLn $ "Right branch pattern: " ++ eitherAnalysis.rightBranch.pattern
  putStrLn $ "Can prune Left: " ++ show eitherAnalysis.canPruneLeft

  -- Verify Left is identified as early exit (error propagation)
  let leftIsEarly = eitherAnalysis.leftBranch.reachability == EarlyExit

  if leftIsEarly
     then putStrLn "[PASS] Either paths analyzed correctly"
     else putStrLn "[FAIL] Left should be EarlyExit"

  putStrLn ""
  putStrLn "=== Done ==="
