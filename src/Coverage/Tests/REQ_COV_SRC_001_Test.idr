-- Test for REQ_COV_SRC_001: Extract export declarations from .idr files
module Main

import Coverage.SourceAnalyzer
import Data.List
import Data.String

sampleSource : String
sampleSource = """
module TestModule

export
add : Int -> Int -> Int
add x y = x + y

export
mul : Int -> Int -> Int
mul x y = x * y
"""

main : IO ()
main = do
  putStrLn "=== REQ_COV_SRC_001 Test ==="
  putStrLn "Testing: Extract export declarations"

  -- Use actual analyzeSource from Coverage.SourceAnalyzer
  let funcs = analyzeSource sampleSource
  let count = length funcs

  putStrLn $ "Exported functions found: " ++ show count
  if count >= 1
     then putStrLn "[PASS] Found exported functions"
     else putStrLn "[FAIL] Expected exported functions"
  putStrLn "=== Done ==="
