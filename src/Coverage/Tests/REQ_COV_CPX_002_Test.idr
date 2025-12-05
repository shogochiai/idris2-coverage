-- Test for REQ_COV_CPX_002: Determine if function should split
module Main

import Coverage.Complexity
import Coverage.Types
import Data.List

main : IO ()
main = do
  putStrLn "=== REQ_COV_CPX_002 Test ==="
  putStrLn "Testing: Determine if function should split"
  putStrLn ""

  -- Low complexity factors (should not split)
  let lowFactors = MkComplexityFactors 0 0 0 0 0 10
  let shouldSplitLow = shouldSplit defaultComplexityConfig lowFactors

  -- High complexity factors (should split)
  let highFactors = MkComplexityFactors 20 20 15 10 10 75
  let shouldSplitHigh = shouldSplit defaultComplexityConfig highFactors

  putStrLn $ "Low complexity (score 10) should split: " ++ show shouldSplitLow
  putStrLn $ "High complexity (score 75) should split: " ++ show shouldSplitHigh

  -- Verify split recommendation
  let correct = not shouldSplitLow && shouldSplitHigh

  if correct
     then putStrLn "[PASS] Split decision correct"
     else putStrLn "[FAIL] Split decision incorrect"

  putStrLn ""
  putStrLn "=== Done ==="
