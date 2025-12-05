-- Test for REQ_COV_PTH_001: Detect Nothing/Left/Nil early exits
module Main

import Coverage.PathAnalysis
import Coverage.Types
import Data.List
import Data.Maybe

main : IO ()
main = do
  putStrLn "=== REQ_COV_PTH_001 Test ==="
  putStrLn "Testing: Detect Nothing/Left/Nil early exits"
  putStrLn ""

  -- Test early exit pattern detection
  let nothingPat = isEarlyExitPattern "Nothing"
  let leftPat = isEarlyExitPattern "Left _"
  let nilPat = isEarlyExitPattern "[]"
  let justPat = isEarlyExitPattern "Just x"

  putStrLn $ "Nothing is early exit: " ++ show (isJust nothingPat)
  putStrLn $ "Left _ is early exit: " ++ show (isJust leftPat)
  putStrLn $ "[] is early exit: " ++ show (isJust nilPat)
  putStrLn $ "Just x is early exit: " ++ show (isJust justPat)

  -- Verify correct detection
  let correct = isJust nothingPat && isJust leftPat && isJust nilPat && not (isJust justPat)

  if correct
     then putStrLn "[PASS] Early exit patterns detected correctly"
     else putStrLn "[FAIL] Early exit detection incorrect"

  putStrLn ""
  putStrLn "=== Done ==="
