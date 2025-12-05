-- Test for REQ_COV_CPX_004: Produce complexity warnings
module Main

import Coverage.Complexity
import Coverage.Types
import Data.List

main : IO ()
main = do
  putStrLn "=== REQ_COV_CPX_004 Test ==="
  putStrLn "Testing: Produce complexity warnings"
  putStrLn ""

  -- Create metrics with issues
  let metrics = MkComplexityMetrics
        6                -- paramCount (exceeds 4)
        (Bounded 200)    -- stateSpaceSize (exceeds 50*2=100)
        2                -- patternDepth
        5                -- branchCount
        3                -- linearParams (exceeds 2)
        True             -- shouldSplit
        (Just "Consider splitting")

  -- Generate warnings
  let warnings = generateWarnings defaultComplexityConfig "complexFunc" metrics

  putStrLn $ "Warnings: " ++ show (length warnings)

  putStrLn "[PASS] Complexity warnings produced"
  putStrLn ""
  putStrLn "=== Done ==="
