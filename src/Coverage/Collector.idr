||| Profile data collector from Chez Scheme profiler output
||| REQ_COV_COL_001 - REQ_COV_COL_004
module Coverage.Collector

import Coverage.Types
import Data.List
import Data.List1
import Data.Maybe
import Data.String
import System.File

%default total

-- =============================================================================
-- Helper Functions
-- =============================================================================

||| Get first character of string, or Nothing if empty
firstChar : String -> Maybe Char
firstChar s = case unpack s of
                [] => Nothing
                (c :: _) => Just c

||| Index into a list safely
indexList : List a -> Nat -> Maybe a
indexList [] _ = Nothing
indexList (x :: _) Z = Just x
indexList (_ :: xs) (S n) = indexList xs n

||| Zip a list with indices starting from 1
zipWithIndex : List a -> List (Nat, a)
zipWithIndex = go 1
  where
    go : Nat -> List a -> List (Nat, a)
    go _ [] = []
    go n (x :: xs) = (n, x) :: go (S n) xs

-- =============================================================================
-- Scheme Source Parsing
-- =============================================================================

||| Parse (define ModuleName-funcName ...) from .ss file
||| Returns list of (schemeFunc, lineNumber)
export
parseSchemeDefs : String -> List (String, Nat)
parseSchemeDefs content =
  let ls = zipWithIndex (lines content)
  in mapMaybe parseLine ls
  where
    parseLine : (Nat, String) -> Maybe (String, Nat)
    parseLine (lineNum, line) =
      if isPrefixOf "(define " (trim line)
         then
           let afterDefine = pack $ drop 8 $ unpack (trim line)
               funcName = pack $ takeWhile (\c => c /= ' ' && c /= '(') (unpack afterDefine)
           in if funcName /= "" && isInfixOf "-" funcName
                 then Just (funcName, lineNum)
                 else Nothing
         else Nothing

-- =============================================================================
-- Profile HTML Parsing
-- =============================================================================

||| Parse hot spots from profile.html content
||| REQ_COV_COL_001: Parse profile.html Hot Spots table
||| REQ_COV_COL_002: Extract function name and hit count
export
parseProfileHtml : String -> List ProfileHit
parseProfileHtml content =
  -- Hot Spots are in table rows with class pc1-pc12
  let ls = lines content
      hotSpotLines = filter isHotSpotLine ls
  in mapMaybe parseHotSpotRow hotSpotLines
  where
    isHotSpotLine : String -> Bool
    isHotSpotLine line = isInfixOf "pc" line && isInfixOf "line" line && isInfixOf "(" line

    parseParenCount : String -> Maybe Nat
    parseParenCount s =
      let stripped = pack $ filter (\c => c >= '0' && c <= '9') (unpack s)
      in parsePositive stripped

    parseHotSpotRow : String -> Maybe ProfileHit
    parseHotSpotRow line =
      -- Extract: line number and count from "line N (count)"
      let parts = words line
      in findLineCount parts
      where
        findLineCount : List String -> Maybe ProfileHit
        findLineCount [] = Nothing
        findLineCount (x :: xs) =
          if x == "line"
             then case xs of
                    (numStr :: rest) =>
                      case parsePositive numStr of
                        Nothing => findLineCount xs
                        Just lineNum =>
                          let countStr = fromMaybe "" $ head' rest
                              count = parseParenCount countStr
                          in case count of
                               Nothing => findLineCount xs
                               Just c => Just $ MkProfileHit "" c "" lineNum
                    _ => findLineCount xs
             else findLineCount xs

-- =============================================================================
-- Annotated Scheme HTML Parsing (.ss.html)
-- =============================================================================

||| Expression-level coverage from annotated .ss.html file
||| Format: <span class=pcN title="line L char C count N">...</span>
public export
record ExprCoverage where
  constructor MkExprCoverage
  line : Nat
  char : Nat
  count : Nat

||| Parse title="line L char C count N"
parseSpanTitle : String -> Maybe ExprCoverage
parseSpanTitle s =
  -- title="line 747 char 77 count 6"
  let parts = words s
  in findParts parts Nothing Nothing Nothing
  where
    findParts : List String -> Maybe Nat -> Maybe Nat -> Maybe Nat -> Maybe ExprCoverage
    findParts [] (Just l) (Just c) (Just cnt) = Just $ MkExprCoverage l c cnt
    findParts [] _ _ _ = Nothing
    findParts (x :: xs) ml mc mcnt =
      if x == "line"
         then case xs of
                (n :: rest) => case parsePositive n of
                                 Just ln => findParts rest (Just ln) mc mcnt
                                 Nothing => findParts xs ml mc mcnt
                _ => findParts xs ml mc mcnt
         else if x == "char"
         then case xs of
                (n :: rest) => case parsePositive n of
                                 Just ch => findParts rest ml (Just ch) mcnt
                                 Nothing => findParts xs ml mc mcnt
                _ => findParts xs ml mc mcnt
         else if x == "count"
         then case xs of
                (n :: rest) => case parsePositive n of
                                 Just ct => findParts rest ml mc (Just ct)
                                 Nothing => findParts xs ml mc mcnt
                _ => findParts xs ml mc mcnt
         else findParts xs ml mc mcnt

||| Extract all title="..." attributes from HTML
||| Note: Uses assert_total for recursion on String parsing
export
extractTitles : String -> List String
extractTitles content = go (unpack content) []
  where
    go : List Char -> List String -> List String
    go [] acc = reverse acc
    go ('t' :: 'i' :: 't' :: 'l' :: 'e' :: '=' :: '"' :: rest) acc =
      let (title, remaining) = break (== '"') rest
      in assert_total $ go remaining (pack title :: acc)
    go (_ :: rest) acc = assert_total $ go rest acc

||| Parse annotated .ss.html for expression-level coverage
export
parseAnnotatedHtml : String -> List ExprCoverage
parseAnnotatedHtml content =
  let titles = extractTitles content
  in mapMaybe parseSpanTitle titles

||| Group expressions by Scheme line and calculate coverage
||| Returns: List (schemeLineNum, executedExprs, totalExprs)
export
groupByLine : List ExprCoverage -> List (Nat, Nat, Nat)
groupByLine exprs =
  let sorted = sortBy (\a, b => compare a.line b.line) exprs
      grouped = groupBy (\a, b => a.line == b.line) sorted
  in map summarize grouped
  where
    summarize : List1 ExprCoverage -> (Nat, Nat, Nat)
    summarize (e ::: es) =
      let expList = e :: es
      in (e.line, length (filter (\x => x.count > 0) expList), length expList)

||| Calculate function-level coverage from expression data
||| Given: function definitions (name, startLine) and expression coverage
export
calculateFunctionCoverage : List (String, Nat) -> List ExprCoverage -> List (String, Nat, Nat, Double)
calculateFunctionCoverage defs exprs =
  -- Sort definitions by line number
  let sortedDefs = sortBy (\(_, l1), (_, l2) => compare l1 l2) defs
  in zipWithRanges sortedDefs
  where
    -- Pair each function with its line range
    calcPct : List ExprCoverage -> (Nat, Nat, Double)
    calcPct funcExprs =
      let totl = length funcExprs
          exec = length (filter (\e => e.count > 0) funcExprs)
          pct = if totl == 0 then 100.0 else cast exec / cast totl * 100.0
      in (exec, totl, pct)

    zipWithRanges : List (String, Nat) -> List (String, Nat, Nat, Double)
    zipWithRanges [] = []
    zipWithRanges [(name, start)] =
      -- Last function extends to end
      let funcExprs = filter (\e => e.line >= start) exprs
          result = calcPct funcExprs
      in [(name, fst result, fst (snd result), snd (snd result))]
    zipWithRanges ((name, start) :: (next, nextStart) :: rest) =
      let funcExprs = filter (\e => e.line >= start && e.line < nextStart) exprs
          result = calcPct funcExprs
      in (name, fst result, fst (snd result), snd (snd result)) :: zipWithRanges ((next, nextStart) :: rest)

-- =============================================================================
-- Combined Collection
-- =============================================================================

||| Collect profile data by matching HTML hits with Scheme definitions
||| REQ_COV_COL_003: Parse .ss file for definitions
||| REQ_COV_COL_004: Return List ProfileHit
export
collectProfile : (htmlContent : String) -> (schemeContent : String) -> List ProfileHit
collectProfile htmlContent schemeContent =
  let htmlHits = parseProfileHtml htmlContent
      schemeDefs = parseSchemeDefs schemeContent
      -- Match line numbers to function names
  in mapMaybe (matchHit schemeDefs) htmlHits
  where
    matchHit : List (String, Nat) -> ProfileHit -> Maybe ProfileHit
    matchHit defs hit =
      -- Find the definition that matches this line (or closest before)
      let matching = filter (\(_, l) => l <= hit.line) defs
      in case last' matching of
           Nothing => Just hit  -- Keep hit even without match
           Just (funcName, _) => Just $ { schemeFunc := funcName } hit

-- =============================================================================
-- File Reading (partial - involves IO)
-- =============================================================================

||| Read profile.html and .ss file, return collected profile hits
export
covering
collectFromFiles : (htmlPath : String) -> (schemePath : String) -> IO (Either String (List ProfileHit))
collectFromFiles htmlPath schemePath = do
  Right htmlContent <- readFile htmlPath
    | Left err => pure $ Left "Failed to read \{htmlPath}: \{show err}"
  Right schemeContent <- readFile schemePath
    | Left err => pure $ Left "Failed to read \{schemePath}: \{show err}"
  pure $ Right $ collectProfile htmlContent schemeContent
