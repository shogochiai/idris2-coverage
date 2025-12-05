-- Test for REQ_COV_COL_001: Parse profile.html Hot Spots table
module Main

import Coverage.Collector
import Coverage.Types
import Data.List
import Data.String

sampleProfileHtml : String
sampleProfileHtml = """
<table>
<tr><td class=pc12><a href="sample.ss.html#line702">path line 702 (6)</a></td></tr>
<tr><td class=pc8><a href="sample.ss.html#line100">path line 100 (1)</a></td></tr>
</table>
"""

main : IO ()
main = do
  putStrLn "=== REQ_COV_COL_001 Test ==="
  putStrLn "Testing: Parse profile.html Hot Spots table"
  putStrLn ""

  -- Use actual parseProfileHtml from Coverage.Collector
  let hits = parseProfileHtml sampleProfileHtml
  let count = length hits

  putStrLn $ "Hot spots found: " ++ show count
  if count >= 1
     then putStrLn "[PASS] Parsed hot spot entries"
     else putStrLn "[FAIL] Expected hot spots"

  putStrLn ""
  putStrLn "=== Done ==="
