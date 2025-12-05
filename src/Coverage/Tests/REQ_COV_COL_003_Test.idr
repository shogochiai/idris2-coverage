-- Test for REQ_COV_COL_003: Parse .ss file for (define Module-func ...) patterns
module Main

import Coverage.Collector
import Coverage.Types
import Data.List

sampleScheme : String
sampleScheme = """
(define PreludeC-45Types-fastPack (lambda (x) x))
(define MyModC-45Utils-helper (lambda (x) x))
(define MyModC-45Utils-process (lambda (x y) (+ x y)))
"""

main : IO ()
main = do
  putStrLn "=== REQ_COV_COL_003 Test ==="
  putStrLn "Testing: Parse .ss file for define patterns"

  let defs = parseSchemeDefs sampleScheme

  putStrLn $ "Definitions parsed: " ++ show (length defs)
  if length defs == 3
     then putStrLn "[PASS] Parsed all define patterns"
     else putStrLn "[FAIL] Expected 3 definitions"
  putStrLn "=== Done ==="
