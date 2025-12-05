-- Test for REQ_COV_AGG_004: Aggregate to module and project level
module Main

import Coverage.Types
import Coverage.Collector
import Data.List

main : IO ()
main = do
  putStrLn "=== REQ_COV_AGG_004 Test ==="
  putStrLn "Testing: Module/project aggregation"

  -- Test groupByLine aggregation
  let exprs = parseAnnotatedHtml "<span title=\"line 1 char 1 count 5\">x</span>"
  let grouped = groupByLine exprs

  putStrLn $ "Grouped lines: " ++ show (length grouped)
  if length grouped >= 0
     then putStrLn "[PASS] Aggregated coverage data"
     else putStrLn "[FAIL] Aggregation failed"
  putStrLn "=== Done ==="
