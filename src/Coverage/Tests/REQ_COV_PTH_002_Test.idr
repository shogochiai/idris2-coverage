-- Test for REQ_COV_PTH_002: Analyze Maybe parameter paths
module Main

import Coverage.PathAnalysis
import Coverage.Types
import Data.List

main : IO ()
main = do
  putStrLn "=== REQ_COV_PTH_002 Test ==="
  putStrLn "Testing: Analyze Maybe parameter paths"
  putStrLn ""

  -- Analyze Maybe parameter
  let maybeAnalysis = analyzeMaybePaths "config"

  putStrLn $ "Parameter: " ++ maybeAnalysis.paramName
  putStrLn $ "Nothing branch pattern: " ++ maybeAnalysis.nothingBranch.pattern
  putStrLn $ "Just branch pattern: " ++ maybeAnalysis.justBranch.pattern
  putStrLn $ "Can prune Nothing: " ++ show maybeAnalysis.canPruneNothing

  -- Verify Nothing is identified as early exit
  let nothingIsEarly = maybeAnalysis.nothingBranch.reachability == EarlyExit

  if nothingIsEarly
     then putStrLn "[PASS] Maybe paths analyzed correctly"
     else putStrLn "[FAIL] Nothing should be EarlyExit"

  putStrLn ""
  putStrLn "=== Done ==="
