||| Test hint generation for coverage gaps
||| Provides actionable hints for generating missing tests
module Coverage.TestHint

import Data.List
import Data.Maybe
import Data.String

import Coverage.Types
import Coverage.Linearity
import Coverage.TypeAnalyzer
import Coverage.StateSpace
import Coverage.PathAnalysis

%default total

-- =============================================================================
-- Test Hint Types
-- =============================================================================

||| Priority level for test hints
public export
data HintPriority : Type where
  Critical   : HintPriority    -- Must have (core functionality)
  Important  : HintPriority    -- Should have (error handling)
  Nice       : HintPriority    -- Good to have (edge cases)
  Optional   : HintPriority    -- Low priority (exhaustive)

public export
Show HintPriority where
  show Critical  = "CRITICAL"
  show Important = "IMPORTANT"
  show Nice      = "NICE"
  show Optional  = "OPTIONAL"

public export
Eq HintPriority where
  Critical  == Critical  = True
  Important == Important = True
  Nice      == Nice      = True
  Optional  == Optional  = True
  _         == _         = False

priorityToNat : HintPriority -> Nat
priorityToNat Critical  = 4
priorityToNat Important = 3
priorityToNat Nice      = 2
priorityToNat Optional  = 1

public export
Ord HintPriority where
  compare p1 p2 = compare (priorityToNat p1) (priorityToNat p2)

||| Category of test hint
public export
data HintCategory : Type where
  HappyPath      : HintCategory    -- Normal successful execution
  ErrorPath      : HintCategory    -- Error handling (Nothing, Left)
  BoundaryCase   : HintCategory    -- Edge values (0, empty, max)
  NegativeTest   : HintCategory    -- Invalid input handling
  LinearResource : HintCategory    -- Resource lifecycle
  StateTransition: HintCategory    -- State machine coverage

public export
Show HintCategory where
  show HappyPath       = "happy_path"
  show ErrorPath       = "error_path"
  show BoundaryCase    = "boundary"
  show NegativeTest    = "negative"
  show LinearResource  = "linear_resource"
  show StateTransition = "state_transition"

public export
Eq HintCategory where
  HappyPath       == HappyPath       = True
  ErrorPath       == ErrorPath       = True
  BoundaryCase    == BoundaryCase    = True
  NegativeTest    == NegativeTest    = True
  LinearResource  == LinearResource  = True
  StateTransition == StateTransition = True
  _               == _               = False

||| A single parameter value hint
public export
record ParamHint where
  constructor MkParamHint
  paramName  : String
  paramType  : String
  value      : String           -- Suggested value or pattern
  rationale  : String           -- Why this value

public export
Show ParamHint where
  show h = h.paramName ++ " = " ++ h.value ++ " -- " ++ h.rationale

||| A complete test hint
public export
record TestHint where
  constructor MkTestHint
  funcName     : String
  funcSig      : String
  category     : HintCategory
  priority     : HintPriority
  description  : String
  paramHints   : List ParamHint
  expectedBehavior : String     -- What should happen
  codeTemplate : String         -- Idris test code template

public export
Show TestHint where
  show h = "[" ++ show h.priority ++ "] " ++ h.funcName ++ " - " ++ h.description

-- =============================================================================
-- Helper Functions (Top Level)
-- =============================================================================

happyValueFor : String -> String
happyValueFor "Bool"   = "True"
happyValueFor "Nat"    = "1"
happyValueFor "Int"    = "42"
happyValueFor "String" = "\"test\""
happyValueFor "Char"   = "'a'"
happyValueFor ty =
  if isPrefixOf "Maybe" ty then "Just _"
  else if isPrefixOf "Either" ty then "Right _"
  else if isPrefixOf "List" ty then "[x]"
  else "_valid_"

happyParamHint : LinearParam -> ParamHint
happyParamHint p =
  let name = fromMaybe "_" p.paramName
      val = happyValueFor p.paramType
  in MkParamHint name p.paramType val "Typical valid value"

generateHappyTemplate : String -> List ParamHint -> String
generateHappyTemplate name hints =
  let args = fastConcat $ intersperse " " $ map (.value) hints
  in "test_" ++ name ++ "_happy : IO Bool\n"
  ++ "test_" ++ name ++ "_happy = do\n"
  ++ "  let result = " ++ name ++ " " ++ args ++ "\n"
  ++ "  pure $ isExpected result\n"

generateLinearTemplate : String -> String -> String
generateLinearTemplate fname pname =
  "test_" ++ fname ++ "_linear_" ++ pname ++ " : IO Bool\n"
  ++ "test_" ++ fname ++ "_linear_" ++ pname ++ " = do\n"
  ++ "  " ++ pname ++ " <- acquire\n"
  ++ "  result <- " ++ fname ++ " " ++ pname ++ "\n"
  ++ "  -- " ++ pname ++ " is now consumed\n"
  ++ "  pure $ isSuccess result\n"

generateErrorTemplate : String -> String -> String -> String
generateErrorTemplate fname pname val =
  "test_" ++ fname ++ "_" ++ pname ++ "_error : IO Bool\n"
  ++ "test_" ++ fname ++ "_" ++ pname ++ "_error = do\n"
  ++ "  let result = " ++ fname ++ " " ++ val ++ " ...\n"
  ++ "  pure $ isErrorHandled result\n"

generateBoundaryTemplate : String -> String -> String -> String
generateBoundaryTemplate fname pname val =
  "test_" ++ fname ++ "_" ++ pname ++ "_boundary : IO Bool\n"
  ++ "test_" ++ fname ++ "_" ++ pname ++ "_boundary = do\n"
  ++ "  let result = " ++ fname ++ " " ++ val ++ " ...\n"
  ++ "  pure $ isExpected result\n"

generateCombinationTemplate : String -> List (String, String) -> String
generateCombinationTemplate fname params =
  let args = fastConcat $ intersperse " " $ map snd params
      suffix = fastConcat $ intersperse "_" $ map fst params
  in "test_" ++ fname ++ "_" ++ suffix ++ " : IO Bool\n"
  ++ "test_" ++ fname ++ "_" ++ suffix ++ " = do\n"
  ++ "  let result = " ++ fname ++ " " ++ args ++ "\n"
  ++ "  pure $ isExpected result\n"

linearResourceHint : AnalyzedFunction -> LinearParam -> TestHint
linearResourceHint f p =
  let name = fromMaybe "_" p.paramName
  in MkTestHint
       f.name
       f.signature
       LinearResource
       Critical
       ("Linear resource '" ++ name ++ "' is properly consumed")
       [MkParamHint name p.paramType "_acquired_" "Acquired resource"]
       "Resource is consumed exactly once"
       (generateLinearTemplate f.name name)

-- =============================================================================
-- Happy Path Hints
-- =============================================================================

||| Generate happy path hints for a function
||| These are the "golden path" test cases that should always exist
export
happyPathHints : AnalyzedFunction -> List TestHint
happyPathHints func =
  let paramHints = map happyParamHint func.params
      template = generateHappyTemplate func.name paramHints
      baseHint = MkTestHint
                   func.name
                   func.signature
                   HappyPath
                   Critical
                   "Basic successful execution with valid inputs"
                   paramHints
                   "Function returns expected result without errors"
                   template
      linearParams = filter isLinear func.params
      linearHints = map (linearResourceHint func) linearParams
  in baseHint :: linearHints

-- =============================================================================
-- Error Path Hints
-- =============================================================================

nothingHint : AnalyzedFunction -> LinearParam -> TestHint
nothingHint f p =
  let name = fromMaybe "_" p.paramName
  in MkTestHint
       f.name
       f.signature
       ErrorPath
       Important
       ("Handle Nothing case for '" ++ name ++ "'")
       [MkParamHint name p.paramType "Nothing" "Error/absent case"]
       "Function handles missing value gracefully"
       (generateErrorTemplate f.name name "Nothing")

leftHint : AnalyzedFunction -> LinearParam -> TestHint
leftHint f p =
  let name = fromMaybe "_" p.paramName
  in MkTestHint
       f.name
       f.signature
       ErrorPath
       Important
       ("Handle Left (error) case for '" ++ name ++ "'")
       [MkParamHint name p.paramType "Left err" "Error case"]
       "Function propagates or handles error"
       (generateErrorTemplate f.name name "Left TestError")

-- =============================================================================
-- Boundary Hints
-- =============================================================================

boundaryValuesFor : String -> List (String, String)
boundaryValuesFor "Nat"    = [("0", "Zero"), ("1", "One")]
boundaryValuesFor "Int"    = [("0", "Zero"), ("-1", "Negative"), ("maxInt", "Maximum")]
boundaryValuesFor "String" = [("\"\"", "Empty"), ("\"a\"", "Single char")]
boundaryValuesFor ty =
  if isPrefixOf "List" ty then [("[]", "Empty list"), ("[x]", "Singleton")]
  else []

mkBoundaryHint : AnalyzedFunction -> String -> String -> (String, String) -> TestHint
mkBoundaryHint f name ty (val, desc) =
  MkTestHint
    f.name
    f.signature
    BoundaryCase
    Nice
    ("Boundary case: " ++ name ++ " = " ++ desc)
    [MkParamHint name ty val desc]
    "Function handles boundary value correctly"
    (generateBoundaryTemplate f.name name val)

boundaryHintsFor : AnalyzedFunction -> LinearParam -> List TestHint
boundaryHintsFor f p =
  let name = fromMaybe "_" p.paramName
      boundaries = boundaryValuesFor p.paramType
  in map (mkBoundaryHint f name p.paramType) boundaries

-- =============================================================================
-- Combination Hints
-- =============================================================================

categoryFromString : String -> HintCategory
categoryFromString "error"    = ErrorPath
categoryFromString "boundary" = BoundaryCase
categoryFromString "happy"    = HappyPath
categoryFromString _          = HappyPath

suggestionToHint : AnalyzedFunction -> EstimatedTestCase -> TestHint
suggestionToHint f tc =
  let paramHints = map (\pv => MkParamHint (fst pv) "?" (snd pv) "Suggested value") tc.paramValues
      prio = case tc.category of
        "error" => Important
        "boundary" => Nice
        _ => Optional
  in MkTestHint
       f.name
       f.signature
       (categoryFromString tc.category)
       prio
       ("Combination: " ++ show tc.paramValues)
       paramHints
       "Verify behavior for this input combination"
       (generateCombinationTemplate f.name tc.paramValues)

-- =============================================================================
-- Exhaustive Path Hints
-- =============================================================================

||| Generate exhaustive path hints for full coverage
||| These cover all combinations and edge cases
export
exhaustivePathHints : StateSpaceConfig -> AnalyzedFunction -> List TestHint
exhaustivePathHints cfg func =
  let maybeParams = filter (isPrefixOf "Maybe" . (.paramType)) func.params
      eitherParams = filter (isPrefixOf "Either" . (.paramType)) func.params
      errorHints = map (nothingHint func) maybeParams ++ map (leftHint func) eitherParams
      boundaryHints = concatMap (boundaryHintsFor func) func.params
      suggested = suggestTestCases cfg func
      combinationHints = map (suggestionToHint func) (take 10 suggested)
  in errorHints ++ boundaryHints ++ combinationHints

-- =============================================================================
-- Test Hint Report
-- =============================================================================

||| Complete test hint report for a function
public export
record FunctionTestHints where
  constructor MkFunctionTestHints
  funcName      : String
  funcSig       : String
  happyPaths    : List TestHint
  exhaustive    : List TestHint
  totalHints    : Nat
  criticalCount : Nat
  importantCount: Nat

export
Show FunctionTestHints where
  show h = h.funcName ++ ": " ++ show h.totalHints ++ " hints ("
        ++ show h.criticalCount ++ " critical, "
        ++ show h.importantCount ++ " important)"

||| Generate all hints for a function
export
generateTestHints : StateSpaceConfig -> AnalyzedFunction -> FunctionTestHints
generateTestHints cfg func =
  let happy = happyPathHints func
      exh = exhaustivePathHints cfg func
      allHints = happy ++ exh
      critical = length $ filter (\h => h.priority == Critical) allHints
      important = length $ filter (\h => h.priority == Important) allHints
  in MkFunctionTestHints
       func.name
       func.signature
       happy
       exh
       (length allHints)
       critical
       important

-- =============================================================================
-- Hint Filtering and Prioritization
-- =============================================================================

||| Filter hints by priority
export
filterByPriority : HintPriority -> List TestHint -> List TestHint
filterByPriority minPrio = filter (\h => h.priority >= minPrio)

||| Filter hints by category
export
filterByCategory : HintCategory -> List TestHint -> List TestHint
filterByCategory cat = filter (\h => h.category == cat)

||| Get only critical and important hints (minimal test suite)
export
minimalTestSuite : FunctionTestHints -> List TestHint
minimalTestSuite hints =
  filterByPriority Important (hints.happyPaths ++ hints.exhaustive)

||| Get all hints sorted by priority
export
allHintsSorted : FunctionTestHints -> List TestHint
allHintsSorted hints =
  let allH = hints.happyPaths ++ hints.exhaustive
  in sortBy (\h1, h2 => compare h2.priority h1.priority) allH

-- =============================================================================
-- Code Generation Helpers
-- =============================================================================

||| Generate test module header
export
generateTestModuleHeader : String -> String
generateTestModuleHeader moduleName =
  "module " ++ moduleName ++ "_Test\n\n"
  ++ "import " ++ moduleName ++ "\n"
  ++ "import Test.Unit  -- or your test framework\n\n"

||| Generate test code from hints
export
generateTestCode : FunctionTestHints -> String
generateTestCode hints =
  let criticalTests = filterByPriority Critical (hints.happyPaths ++ hints.exhaustive)
      importantTests = filter (\h => h.priority == Important) (hints.happyPaths ++ hints.exhaustive)
      niceTests = filter (\h => h.priority == Nice) (hints.happyPaths ++ hints.exhaustive)
  in "-- Critical Tests (MUST have)\n"
  ++ fastConcat (map (.codeTemplate) criticalTests)
  ++ "\n-- Important Tests (SHOULD have)\n"
  ++ fastConcat (map (.codeTemplate) importantTests)
  ++ "\n-- Nice-to-have Tests\n"
  ++ fastConcat (map (.codeTemplate) niceTests)

-- =============================================================================
-- JSON Output for Hints
-- =============================================================================

escapeChar : Char -> String
escapeChar '\n' = "\\n"
escapeChar '"'  = "\\\""
escapeChar '\\' = "\\\\"
escapeChar c    = singleton c

escapeChars : String -> String
escapeChars s = fastConcat $ map escapeChar (unpack s)

escapeJson : String -> String
escapeJson s = "\"" ++ escapeChars s ++ "\""

paramJson : ParamHint -> String
paramJson p =
  "{\"name\": \"" ++ p.paramName
  ++ "\", \"type\": \"" ++ p.paramType
  ++ "\", \"value\": \"" ++ p.value
  ++ "\", \"rationale\": \"" ++ p.rationale ++ "\"}"

paramHintsJson : List ParamHint -> String
paramHintsJson ps = fastConcat $ intersperse ", " $ map paramJson ps

||| Convert hint to JSON string
export
hintToJson : TestHint -> String
hintToJson h =
  "{\n"
  ++ "  \"function\": \"" ++ h.funcName ++ "\",\n"
  ++ "  \"category\": \"" ++ show h.category ++ "\",\n"
  ++ "  \"priority\": \"" ++ show h.priority ++ "\",\n"
  ++ "  \"description\": \"" ++ h.description ++ "\",\n"
  ++ "  \"params\": [" ++ paramHintsJson h.paramHints ++ "],\n"
  ++ "  \"expected_behavior\": \"" ++ h.expectedBehavior ++ "\",\n"
  ++ "  \"code_template\": " ++ escapeJson h.codeTemplate ++ "\n"
  ++ "}"

||| Generate full JSON report for hints
export
hintsToJson : FunctionTestHints -> String
hintsToJson h =
  "{\n"
  ++ "  \"function\": \"" ++ h.funcName ++ "\",\n"
  ++ "  \"signature\": \"" ++ h.funcSig ++ "\",\n"
  ++ "  \"total_hints\": " ++ show h.totalHints ++ ",\n"
  ++ "  \"critical_count\": " ++ show h.criticalCount ++ ",\n"
  ++ "  \"important_count\": " ++ show h.importantCount ++ ",\n"
  ++ "  \"happy_path_hints\": [\n    "
  ++ fastConcat (intersperse ",\n    " (map hintToJson h.happyPaths))
  ++ "\n  ],\n"
  ++ "  \"exhaustive_hints\": [\n    "
  ++ fastConcat (intersperse ",\n    " (map hintToJson h.exhaustive))
  ++ "\n  ]\n"
  ++ "}"

-- =============================================================================
-- Batch Processing
-- =============================================================================

||| Generate hints for all uncovered functions
export
generateHintsForUncovered : StateSpaceConfig -> List AnalyzedFunction -> List FunctionCoverage -> List FunctionTestHints
generateHintsForUncovered cfg funcs coverages =
  let coveredNames = map (.name) $ filter (\c => c.coveragePercent > 0) coverages
      uncovered = filter (\f => not (f.name `elem` coveredNames)) funcs
  in map (generateTestHints cfg) uncovered

||| Summary of hints for a module
public export
record ModuleTestHintSummary where
  constructor MkModuleTestHintSummary
  moduleName       : String
  functionsWithoutTests : Nat
  totalHints       : Nat
  criticalHints    : Nat
  importantHints   : Nat
  functionHints    : List FunctionTestHints

export
Show ModuleTestHintSummary where
  show s = s.moduleName ++ ": " ++ show s.functionsWithoutTests
        ++ " functions need tests, " ++ show s.criticalHints ++ " critical hints"

||| Generate module-level summary
export
summarizeModuleHints : String -> List FunctionTestHints -> ModuleTestHintSummary
summarizeModuleHints modName hints =
  let totalH = sum $ map (.totalHints) hints
      criticalH = sum $ map (.criticalCount) hints
      importantH = sum $ map (.importantCount) hints
  in MkModuleTestHintSummary modName (length hints) totalH criticalH importantH hints
