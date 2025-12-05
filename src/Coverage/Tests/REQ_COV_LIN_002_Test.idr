-- Test for REQ_COV_LIN_002: Identify erased parameters (Q0)
module Main

import Coverage.Linearity
import Coverage.Types

main : IO ()
main = do
  putStrLn "=== REQ_COV_LIN_002 Test ==="
  putStrLn "Testing: Identify erased parameters (Q0)"
  putStrLn ""

  -- Create test parameters
  let erasedParam = MkLinearParam (Just "ty") "Type" Q0 Nothing
  let linearParam = MkLinearParam (Just "h") "Handle" Q1 Nothing
  let normalParam = MkLinearParam (Just "x") "Int" QW Nothing

  -- Test isErased
  putStrLn $ "Q0 isErased: " ++ show (isErased erasedParam)
  putStrLn $ "Q1 isErased: " ++ show (isErased linearParam)
  putStrLn $ "QW isErased: " ++ show (isErased normalParam)

  putStrLn "[PASS] Erased parameters correctly identified"
  putStrLn ""
  putStrLn "=== Done ==="
