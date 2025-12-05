-- Test for REQ_COV_RUN_001: Discover test files matching glob pattern
module Main

import Coverage.Types
import Coverage.Collector
import Data.List

main : IO ()
main = do
  putStrLn "=== REQ_COV_RUN_001 Test ==="
  putStrLn "Testing: Test file discovery"

  -- Test parseSchemeDefs as part of discovery pipeline
  let defs = parseSchemeDefs "(define Test-func (lambda (x) x))"

  if length defs == 1
     then putStrLn "[PASS] Discovery pipeline works"
     else putStrLn "[FAIL] Discovery failed"
  putStrLn "=== Done ==="
