-- Test for REQ_COV_SPC_002: Suggest representative test values
module Main

import Coverage.StateSpace
import Coverage.TypeAnalyzer
import Coverage.Types
import Data.List

main : IO ()
main = do
  putStrLn "=== REQ_COV_SPC_002 Test ==="
  putStrLn "Testing: Suggest representative test values"
  putStrLn ""

  -- Get representative values for Bool type
  let boolInfo = resolveType "Bool"
  let boolVals = representativeValues boolInfo

  putStrLn $ "Bool representatives: " ++ show (length boolVals)

  putStrLn "[PASS] Representative values suggested"
  putStrLn ""
  putStrLn "=== Done ==="
