-- Test for REQ_COV_SPC_003: Identify coverage gaps
module Main

import Coverage.StateSpace
import Coverage.TypeAnalyzer
import Coverage.Types
import Data.List

main : IO ()
main = do
  putStrLn "=== REQ_COV_SPC_003 Test ==="
  putStrLn "Testing: Identify coverage gaps"
  putStrLn ""

  -- Create an analyzed function
  let analyzed = analyzeFunction "process" "Maybe Int -> Bool"

  -- Create existing test cases (only testing Just path)
  let existingTests = ["Just 1, True", "Just 0, False"]

  -- Find gaps
  let gaps = findCoverageGaps defaultConfig analyzed existingTests

  putStrLn $ "Existing tests: " ++ show (length existingTests)
  putStrLn $ "Coverage gaps found: " ++ show (length gaps)

  -- There should be gaps for Nothing case
  let hasGaps = length gaps > 0

  if hasGaps
     then putStrLn "[PASS] Coverage gaps identified"
     else putStrLn "[FAIL] Should detect missing Nothing case"

  putStrLn ""
  putStrLn "=== Done ==="
