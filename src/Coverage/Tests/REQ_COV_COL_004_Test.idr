-- Test for REQ_COV_COL_004: Return List ProfileHit
module Main

import Coverage.Collector
import Coverage.Types
import Data.List

sampleAnnotatedHtml : String
sampleAnnotatedHtml = """
<span class=pc2 title="line 10 char 1 count 5">code</span>
<span class=pc1 title="line 11 char 1 count 0">uncovered</span>
"""

main : IO ()
main = do
  putStrLn "=== REQ_COV_COL_004 Test ==="
  putStrLn "Testing: Expression coverage parsing"

  let exprs = parseAnnotatedHtml sampleAnnotatedHtml

  putStrLn $ "Expressions parsed: " ++ show (length exprs)
  if length exprs == 2
     then putStrLn "[PASS] Returned expression coverage list"
     else putStrLn "[FAIL] Expected 2 expressions"
  putStrLn "=== Done ==="
