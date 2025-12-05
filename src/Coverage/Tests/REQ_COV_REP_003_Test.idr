-- Test for REQ_COV_REP_003: Include all required fields per lazy-idris spec
module Main

import Coverage.Types
import Coverage.Report
import Data.String

main : IO ()
main = do
  putStrLn "=== REQ_COV_REP_003 Test ==="
  putStrLn "Testing: Required fields inclusion"

  let fc = coveredFunction "Mod" "func" 10 ["t1"]
  let json = functionCoverageJson fc

  -- Check lazy-idris required fields
  let hasModule = isInfixOf "module" json
  let hasName = isInfixOf "name" json
  let hasCalledBy = isInfixOf "called_by_tests" json
  let hasLineStart = isInfixOf "line_start" json

  if hasModule && hasName && hasCalledBy && hasLineStart
     then putStrLn "[PASS] All lazy-idris fields present"
     else putStrLn "[FAIL] Missing required fields"
  putStrLn "=== Done ==="
