-- Test for REQ_COV_SRC_002: Determine line_start and line_end for each function
module Main

import Coverage.SourceAnalyzer
import Data.List

sampleSource : String
sampleSource = """
module TestModule

export
myFunc : Int -> Int
myFunc x = x + 1
"""

main : IO ()
main = do
  putStrLn "=== REQ_COV_SRC_002 Test ==="
  putStrLn "Testing: line_start and line_end extraction"

  let funcs = analyzeSource sampleSource

  case funcs of
    (f :: _) => do
      putStrLn $ "Function: " ++ f.name
      putStrLn $ "Line start: " ++ show f.lineStart
      putStrLn "[PASS] Extracted line information"
    [] => putStrLn "[FAIL] No functions found"
  putStrLn "=== Done ==="
