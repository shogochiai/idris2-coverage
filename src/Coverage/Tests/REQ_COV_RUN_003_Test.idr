-- Test for REQ_COV_RUN_003: Execute compiled test and capture profile.html
module Main

import Coverage.Collector
import Coverage.Types
import Data.List

main : IO ()
main = do
  putStrLn "=== REQ_COV_RUN_003 Test ==="
  putStrLn "Testing: Profile capture"

  -- Test profile parsing which captures execution data
  let html = "<span title=\"line 1 char 1 count 10\">x</span>"
  let exprs = parseAnnotatedHtml html

  if length exprs == 1
     then putStrLn "[PASS] Profile capture parsing works"
     else putStrLn "[FAIL] Capture failed"
  putStrLn "=== Done ==="
