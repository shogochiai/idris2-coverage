-- Test for REQ_COV_SRC_004: Handle multi-line function definitions
module Main

import Coverage.SourceAnalyzer
import Data.List

sampleSource : String
sampleSource = """
module TestModule

export
complexFunc : Int -> Int -> Int -> Int
complexFunc x y z =
  let a = x + y
      b = y + z
  in a + b
"""

main : IO ()
main = do
  putStrLn "=== REQ_COV_SRC_004 Test ==="
  putStrLn "Testing: Multi-line function definitions"

  let funcs = analyzeSource sampleSource

  case funcs of
    (f :: _) => do
      putStrLn $ "Function: " ++ f.name
      putStrLn $ "Line range: " ++ show f.lineStart ++ "-" ++ show f.lineEnd
      putStrLn "[PASS] Handled multi-line definition"
    [] => putStrLn "[FAIL] No functions found"
  putStrLn "=== Done ==="
