-- Test for REQ_COV_TYP_004: Produce AnalyzedFunction records
module Main

import Coverage.TypeAnalyzer
import Coverage.Types
import Data.List

main : IO ()
main = do
  putStrLn "=== REQ_COV_TYP_004 Test ==="
  putStrLn "Testing: Produce AnalyzedFunction records"
  putStrLn ""

  -- Analyze a function signature
  let analyzed = analyzeFunction "testFunc" "Bool -> Int -> String"

  putStrLn $ "Function name: " ++ analyzed.name
  putStrLn $ "Param count: " ++ show (length analyzed.params)
  putStrLn $ "State space: " ++ show analyzed.stateSpace

  putStrLn "[PASS] AnalyzedFunction record produced"
  putStrLn ""
  putStrLn "=== Done ==="
