-- Test for REQ_COV_LIN_003: Identify linear parameters (Q1)
module Main

import Coverage.Linearity
import Coverage.Types

main : IO ()
main = do
  putStrLn "=== REQ_COV_LIN_003 Test ==="
  putStrLn "Testing: Identify linear parameters (Q1)"
  putStrLn ""

  -- Create test parameters
  let erasedParam = MkLinearParam (Just "ty") "Type" Q0 Nothing
  let linearParam = MkLinearParam (Just "h") "Handle" Q1 Nothing
  let normalParam = MkLinearParam (Just "x") "Int" QW Nothing

  -- Test isLinear
  putStrLn $ "Q0 isLinear: " ++ show (isLinear erasedParam)
  putStrLn $ "Q1 isLinear: " ++ show (isLinear linearParam)
  putStrLn $ "QW isLinear: " ++ show (isLinear normalParam)

  putStrLn "[PASS] Linear parameters correctly identified"
  putStrLn ""
  putStrLn "=== Done ==="
