-- Test for REQ_COV_SRC_003: Extract function signatures
module Main

import Coverage.SourceAnalyzer
import Data.List
import Data.Maybe

sampleSource : String
sampleSource = """
module TestModule

export
calculate : Int -> Int -> Int
calculate x y = x + y
"""

main : IO ()
main = do
  putStrLn "=== REQ_COV_SRC_003 Test ==="
  putStrLn "Testing: Extract function signatures"

  let funcs = analyzeSource sampleSource

  case funcs of
    (f :: _) => do
      putStrLn $ "Function: " ++ f.name
      putStrLn $ "Signature: " ++ fromMaybe "none" f.signature
      if isJust f.signature
         then putStrLn "[PASS] Extracted signature"
         else putStrLn "[FAIL] No signature found"
    [] => putStrLn "[FAIL] No functions found"
  putStrLn "=== Done ==="
