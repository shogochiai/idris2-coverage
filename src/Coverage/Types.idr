||| Coverage type definitions for idris2-coverage
||| REQ_TYPE_COV_001 - REQ_TYPE_COV_005
module Coverage.Types

import Data.List
import Data.List1
import Data.String

%default total

-- =============================================================================
-- Profile Hit (from Chez Scheme profiler)
-- =============================================================================

||| REQ_TYPE_COV_005: Profile hit from Chez Scheme profiler
public export
record ProfileHit where
  constructor MkProfileHit
  schemeFunc : String    -- e.g., "Sample-add"
  hitCount   : Nat
  filePath   : String
  line       : Nat

public export
Show ProfileHit where
  show h = "ProfileHit(\{h.schemeFunc}, \{show h.hitCount}, \{h.filePath}:\{show h.line})"

public export
Eq ProfileHit where
  h1 == h2 = h1.schemeFunc == h2.schemeFunc
          && h1.hitCount == h2.hitCount
          && h1.filePath == h2.filePath
          && h1.line == h2.line

-- =============================================================================
-- Function Coverage
-- =============================================================================

||| REQ_TYPE_COV_001: Function-level coverage data
public export
record FunctionCoverage where
  constructor MkFunctionCoverage
  moduleName      : String          -- "Audit.Orchestrator"
  name            : String          -- "runAudit"
  signature       : Maybe String    -- "AuditOptions -> IO ()"
  lineStart       : Maybe Nat       -- 28
  lineEnd         : Maybe Nat       -- 100
  coveredLines    : Nat             -- 65
  totalLines      : Nat             -- 72
  coveragePercent : Double          -- 90.3
  calledByTests   : List String     -- ["REQ_AUD_ORCH_001", ...]

public export
Show FunctionCoverage where
  show f = "\{f.moduleName}.\{f.name}: \{show f.coveragePercent}%"

public export
Eq FunctionCoverage where
  f1 == f2 = f1.moduleName == f2.moduleName
          && f1.name == f2.name
          && f1.signature == f2.signature
          && f1.lineStart == f2.lineStart
          && f1.lineEnd == f2.lineEnd

||| Create a covered function
public export
coveredFunction : String -> String -> Nat -> List String -> FunctionCoverage
coveredFunction modName funcName hits tests =
  MkFunctionCoverage modName funcName Nothing Nothing Nothing hits hits 100.0 tests

||| Create an uncovered function
public export
uncoveredFunction : String -> String -> FunctionCoverage
uncoveredFunction modName funcName =
  MkFunctionCoverage modName funcName Nothing Nothing Nothing 0 0 0.0 []

-- =============================================================================
-- Module Coverage
-- =============================================================================

||| REQ_TYPE_COV_002: Module-level coverage summary
public export
record ModuleCoverage where
  constructor MkModuleCoverage
  path                : String    -- "src/Audit/Orchestrator.idr"
  functionsTotal      : Nat
  functionsCovered    : Nat
  lineCoveragePercent : Double

public export
Show ModuleCoverage where
  show m = "\{m.path}: \{show m.functionsCovered}/\{show m.functionsTotal} (\{show m.lineCoveragePercent}%)"

public export
Eq ModuleCoverage where
  m1 == m2 = m1.path == m2.path
          && m1.functionsTotal == m2.functionsTotal
          && m1.functionsCovered == m2.functionsCovered

-- =============================================================================
-- Project Coverage
-- =============================================================================

||| REQ_TYPE_COV_003: Project-level coverage summary
public export
record ProjectCoverage where
  constructor MkProjectCoverage
  totalFunctions        : Nat
  coveredFunctions      : Nat
  lineCoveragePercent   : Double
  branchCoveragePercent : Maybe Double  -- Optional

public export
Show ProjectCoverage where
  show p = "Project: \{show p.coveredFunctions}/\{show p.totalFunctions} functions (\{show p.lineCoveragePercent}%)"

public export
Eq ProjectCoverage where
  p1 == p2 = p1.totalFunctions == p2.totalFunctions
          && p1.coveredFunctions == p2.coveredFunctions

-- =============================================================================
-- Coverage Report
-- =============================================================================

||| REQ_TYPE_COV_004: Complete coverage report
public export
record CoverageReport where
  constructor MkCoverageReport
  functions : List FunctionCoverage
  modules   : List ModuleCoverage
  project   : ProjectCoverage

public export
Show CoverageReport where
  show r = "CoverageReport(\{show $ length r.functions} functions, \{show $ length r.modules} modules)"

-- =============================================================================
-- Scheme Function Name Parsing
-- =============================================================================

||| Parse Scheme function name "Module-func" into (module, func)
||| Returns Nothing if format doesn't match
public export
parseSchemeFunc : String -> Maybe (String, String)
parseSchemeFunc s =
  let parts = forget $ split (== '-') s
  in case parts of
       []            => Nothing
       [_]           => Nothing
       (m :: rest)   => Just (m, fastConcat $ intersperse "-" rest)

||| Convert Idris module name to Scheme prefix
||| "Audit.Orchestrator" -> "AuditC-45Orchestrator"
public export
idrisToSchemeModule : String -> String
idrisToSchemeModule modName =
  fastConcat $ intersperse "C-45" $ forget $ split (== '.') modName

||| Check if a Scheme function belongs to a module
public export
belongsToModule : String -> String -> Bool
belongsToModule schemeFunc idrisModule =
  let modPrefix = idrisToSchemeModule idrisModule
  in isPrefixOf modPrefix schemeFunc
