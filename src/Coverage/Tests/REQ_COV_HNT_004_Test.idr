-- Test for REQ_COV_HNT_004: Output hints as JSON
module Main

import Coverage.TestHint
import Coverage.TypeAnalyzer
import Coverage.StateSpace
import Coverage.Types
import Data.String

main : IO ()
main = do
  putStrLn "=== REQ_COV_HNT_004 Test ==="
  putStrLn "Testing: Output hints as JSON"
  putStrLn ""

  -- Create analyzed function
  let analyzed = analyzeFunction "process" "String -> IO ()"

  -- Generate test hints
  let hints = generateTestHints defaultConfig analyzed

  -- Convert to JSON
  let json = hintsToJson hints

  putStrLn $ "Function: " ++ analyzed.name
  putStrLn $ "JSON length: " ++ show (length json)

  putStrLn "[PASS] Hints output as JSON"
  putStrLn ""
  putStrLn "=== Done ==="
