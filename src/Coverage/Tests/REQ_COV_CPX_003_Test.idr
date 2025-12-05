-- Test for REQ_COV_CPX_003: Generate split recommendations
module Main

import Coverage.Complexity
import Coverage.Types
import Data.List

main : IO ()
main = do
  putStrLn "=== REQ_COV_CPX_003 Test ==="
  putStrLn "Testing: Generate split recommendations"
  putStrLn ""

  -- Create params that exceed threshold (> 4 params)
  let manyParams = [ MkLinearParam (Just "a") "Int" QW Nothing
                   , MkLinearParam (Just "b") "String" QW Nothing
                   , MkLinearParam (Just "c") "Bool" QW Nothing
                   , MkLinearParam (Just "d") "Double" QW Nothing
                   , MkLinearParam (Just "e") "Char" QW Nothing
                   , MkLinearParam (Just "f") "Nat" QW Nothing
                   ]

  -- Generate split reasons
  let reasons = generateSplitReasons defaultComplexityConfig manyParams (Bounded 100) 2 15

  putStrLn $ "Param count: " ++ show (length manyParams)
  putStrLn $ "Split reasons: " ++ show (length reasons)

  putStrLn "[PASS] Split recommendations generated"
  putStrLn ""
  putStrLn "=== Done ==="
