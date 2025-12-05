-- Test for REQ_COV_LIN_001: Parse quantity annotations (0/1/ω)
module Main

import Coverage.Linearity
import Coverage.Types
import Data.List

main : IO ()
main = do
  putStrLn "=== REQ_COV_LIN_001 Test ==="
  putStrLn "Testing: Parse quantity annotations (0/1/ω)"
  putStrLn ""

  -- Test parsing Q0 (erased)
  let q0 = parseQuantity "0"
  putStrLn $ "Parse '0': " ++ show q0

  -- Test parsing Q1 (linear)
  let q1 = parseQuantity "1"
  putStrLn $ "Parse '1': " ++ show q1

  -- Test parsing QW (unrestricted)
  let qw = parseQuantity "ω"
  putStrLn $ "Parse 'ω': " ++ show qw

  -- Verify all quantities are recognized correctly
  let correct = q0 == Q0 && q1 == Q1 && qw == QW
  if correct
     then putStrLn "[PASS] All quantity annotations parsed correctly"
     else putStrLn "[FAIL] Failed to parse some quantity annotations"

  putStrLn ""
  putStrLn "=== Done ==="
