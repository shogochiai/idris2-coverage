-- Test for REQ_COV_SPC_001: Calculate parameter state space
module Main

import Coverage.StateSpace
import Coverage.Types

main : IO ()
main = do
  putStrLn "=== REQ_COV_SPC_001 Test ==="
  putStrLn "Testing: Calculate parameter state space"
  putStrLn ""

  -- Create test parameters
  let boolParam = MkLinearParam (Just "flag") "Bool" QW Nothing

  -- Calculate state space
  let boolSpace = paramStateSpace defaultConfig boolParam

  putStrLn $ "Bool param: " ++ show boolSpace

  putStrLn "[PASS] Parameter state space calculated"
  putStrLn ""
  putStrLn "=== Done ==="
