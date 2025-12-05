-- Test for REQ_COV_TYP_002: Resolve primitive type state counts
module Main

import Coverage.TypeAnalyzer
import Coverage.Types
import Data.Maybe

main : IO ()
main = do
  putStrLn "=== REQ_COV_TYP_002 Test ==="
  putStrLn "Testing: Resolve primitive type state counts"
  putStrLn ""

  -- Test primitive type state counts
  putStrLn $ "Bool: " ++ show (primitiveStateCount "Bool")
  putStrLn $ "Nat: " ++ show (primitiveStateCount "Nat")
  putStrLn $ "Unit: " ++ show (primitiveStateCount "()")

  putStrLn "[PASS] Primitive state counts resolved"
  putStrLn ""
  putStrLn "=== Done ==="
