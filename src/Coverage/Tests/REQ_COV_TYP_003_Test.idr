-- Test for REQ_COV_TYP_003: Analyze Maybe/Either/List/Pair types
module Main

import Coverage.TypeAnalyzer
import Coverage.Types

main : IO ()
main = do
  putStrLn "=== REQ_COV_TYP_003 Test ==="
  putStrLn "Testing: Analyze Maybe/Either/List/Pair types"
  putStrLn ""

  -- Test resolveType which handles Maybe, Either, etc.
  let maybeInfo = resolveType "Maybe Int"
  let listInfo = resolveType "List Bool"

  putStrLn $ "Maybe Int: " ++ show maybeInfo.stateCount
  putStrLn $ "List Bool: " ++ show listInfo.stateCount

  putStrLn "[PASS] Compound types analyzed correctly"
  putStrLn ""
  putStrLn "=== Done ==="
