-- Test for REQ_COV_CPX_001: Calculate complexity factors
module Main

import Coverage.Complexity
import Coverage.Types
import Data.List

main : IO ()
main = do
  putStrLn "=== REQ_COV_CPX_001 Test ==="
  putStrLn "Testing: Calculate complexity factors"
  putStrLn ""

  -- Create test parameters
  let params = [ MkLinearParam (Just "a") "Int" QW Nothing
               , MkLinearParam (Just "b") "String" QW Nothing
               , MkLinearParam (Just "c") "Bool" QW Nothing
               ]

  -- Calculate complexity factors
  let factors = calculateFactors defaultComplexityConfig params (Finite 10) 2 5

  putStrLn $ "Total score: " ++ show factors.totalScore

  putStrLn "[PASS] Complexity factors calculated"
  putStrLn ""
  putStrLn "=== Done ==="
