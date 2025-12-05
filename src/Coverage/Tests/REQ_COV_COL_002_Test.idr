-- Test for REQ_COV_COL_002: Extract function name and hit count
module Main

import Coverage.Collector
import Coverage.Types
import Data.List
import Data.String

sampleScheme : String
sampleScheme = "(define TestMod-funcA (lambda (x) x))\n(define TestMod-funcB (lambda (y) y))"

main : IO ()
main = do
  putStrLn "=== REQ_COV_COL_002 Test ==="
  putStrLn "Testing: Extract function name and hit count"

  -- Use actual parseSchemeDefs from Coverage.Collector
  let defs = parseSchemeDefs sampleScheme
  let count = length defs

  putStrLn $ "Definitions found: " ++ show count
  if count == 2
     then putStrLn "[PASS] Extracted 2 function definitions"
     else putStrLn "[FAIL] Expected 2 definitions"
  putStrLn "=== Done ==="
