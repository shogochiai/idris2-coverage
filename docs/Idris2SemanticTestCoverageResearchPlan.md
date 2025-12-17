# Idris2 Semantic Test Coverage Research Plan

## Executive Summary

Current idris2-coverage implementation has a **fundamental architecture mismatch** between the semantic coverage denominator (from `--dumpcases`) and the runtime numerator (from Chez Scheme `.ss.html` profiler). This document analyzes the gap and proposes research directions for true dunham semantic coverage.

---

## 1. Current Architecture Analysis

### 1.1 Denominator: `--dumpcases` Semantic Branches

**Source**: `Coverage/DumpcasesParser.idr`

The `--dumpcases` flag outputs Idris2's compiled case trees:

```
Main.dispatchWith = [0, 1, 2, 3] (%case Main.{arg:0} [(%concase Main.AskCmd 0 0 ...) (%concase Main.DepGraphCmd 1 0 ...) (CRASH "Unhandled input for ...")])
```

**What we extract**:
- `BranchId`: `(moduleName, funcName, caseIndex, branchIndex)`
- `BranchClass`: dunham's classification
  - `BCCanonical`: Reachable branches (test denominator)
  - `BCExcludedNoClauses`: "No clauses in ..." (void/uninhabited, excluded)
  - `BCBugUnhandledInput`: "Unhandled input for ..." (partial code, coverage gap)
  - `BCOptimizerNat`: "Nat case not covered" (optimizer artifact, non-semantic)
  - `BCUnknownCrash`: Other CRASHes (conservative bucket)

**Key data structures**:
```idris
record BranchId where
  constructor MkBranchId
  moduleName  : String    -- "Main"
  funcName    : String    -- "dispatchWith"
  caseIndex   : Nat       -- 0 (which %case block)
  branchIndex : Nat       -- 0,1,2... (which %concase)

record CompiledCase where
  constructor MkCompiledCase
  branchId : BranchId
  kind     : CaseKind     -- Canonical | NonCanonical CrashReason
  pattern  : String
```

### 1.2 Numerator: `.ss.html` Chez Scheme Profiler

**Source**: `Coverage/Collector.idr`

The Chez Scheme profiler generates `.ss.html` with execution counts:

```html
<span class=pc4 title="line 747 char 77 count 6">(case expr ...)</span>
```

**What we extract**:
- `BranchPoint`: `(line, char, branchType, totalBranches, coveredBranches)`
- Looks for Scheme-level patterns: `(if `, `(case `, `(cond `

**Key data structures**:
```idris
record BranchPoint where
  constructor MkBranchPoint
  line            : Nat
  char            : Nat
  branchType      : BranchType  -- IfBranch | CaseBranch | CondBranch
  totalBranches   : Nat
  coveredBranches : Nat
```

### 1.3 The Fundamental Mismatch

```
┌─────────────────────────────────────────────────────────────────────┐
│                    COMPILATION PIPELINE                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  Idris2 Source  ──→  IR (case trees)  ──→  Chez Scheme (.ss)         │
│                           │                        │                  │
│                     --dumpcases                 profiler              │
│                           │                        │                  │
│                           ▼                        ▼                  │
│                      BranchId              .ss.html line hits         │
│                  (module.func.case.branch)  (line 747 count 6)       │
│                           │                        │                  │
│                           └────────────────────────┘                  │
│                                    ❌                                  │
│                            NO MAPPING EXISTS                          │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

**Problem**:
- **Denominator** = Count of `BCCanonical` branches from `--dumpcases` (semantic level)
- **Numerator** = Count of Scheme `(case`/`(if` expressions with hits > 0 (compiled code level)
- These are **different granularities** and **cannot be directly compared**

**Current approximation** (UnifiedRunner.idr:361):
```idris
let executed : Nat = length $ filter (\bp => bp.coveredBranches > 0) branchPoints
```

This counts "Scheme-level branch points executed" NOT "which BranchIds were hit".

---

## 2. Gap Analysis

### 2.1 Why Current Approach Is Wrong

| Aspect | --dumpcases (Semantic) | .ss.html (Profiler) |
|--------|------------------------|---------------------|
| Level | IR case trees | Compiled Scheme |
| Unit | BranchId per %concase | Line/char position |
| Granularity | Per constructor match | Per Scheme expression |
| Identity | Module.Func.Case.Branch | (line, char) |

**Example of mismatch**:
```
--dumpcases output:
Main.dispatch = (%case {arg:0} [
  (%concase AskCmd 0 ...)     -- BranchId: Main.dispatch.0.0
  (%concase HelpCmd 1 ...)    -- BranchId: Main.dispatch.0.1
  (%concase VersionCmd 2 ...) -- BranchId: Main.dispatch.0.2
])

.ss.html profiler:
<span title="line 42 count 10">(case arg0 [...])</span>  -- covers ALL branches
<span title="line 43 count 5">[AskCmd args]</span>       -- one branch
<span title="line 44 count 3">[HelpCmd args]</span>      -- another branch
```

The profiler doesn't tell us:
- Which `BranchId` corresponds to line 43
- If line 43 covers BranchId `Main.dispatch.0.0` or some other case

### 2.2 What True Dunham Coverage Requires

**Formula**: `executed_canonical / total_canonical * 100%`

Where:
- `total_canonical` = Count of `BCCanonical` BranchIds from --dumpcases ✓ (we have this)
- `executed_canonical` = Count of `BCCanonical` BranchIds that were executed at runtime ✗ (missing)

**Required mapping**:
```
BranchId → Set<(SchemeFile, LineNumber)>
```

This mapping **does not exist** in current Idris2 tooling.

---

## 3. Research Directions

### 3.1 Option A: Source Map Generation (Idris2 Compiler Modification)

**Approach**: Modify Idris2 to emit source maps during Chez Scheme codegen

**Pros**:
- Precise BranchId → line mapping
- Theoretically correct solution

**Cons**:
- Requires Idris2 compiler changes
- Maintenance burden
- May not be accepted upstream

**Effort**: High (weeks to months)

### 3.2 Option B: Pattern Matching Heuristics

**Approach**: Infer BranchId → line mapping from naming conventions

**Algorithm sketch**:
```
For each BranchId (mod.func.case.branch):
  1. Find Scheme function: `{mod}C-45{func}`
  2. Find %case at position `case` in that function
  3. Find %concase at position `branch`
  4. Match to .ss.html span at that structure position
```

**Pros**:
- No compiler changes needed
- Can be implemented incrementally

**Cons**:
- Heuristic, not guaranteed correct
- Breaks if codegen changes
- Scheme optimizations may reorder/inline

**Effort**: Medium (days to week)

### 3.3 Option C: IR-Level Instrumentation

**Approach**: Instrument Idris2 IR before Chez Scheme codegen

**Mechanism**:
```idris
-- Before: %case {arg} [(%concase C1 ...) (%concase C2 ...)]
-- After:  %case {arg} [(%concase C1 (log "Main.f.0.0") ...) (%concase C2 (log "Main.f.0.1") ...)]
```

**Pros**:
- Precise, per-BranchId tracking
- No Chez profiler dependency

**Cons**:
- Requires IR transformation pass
- Performance overhead
- Still needs compiler integration

**Effort**: High

### 3.4 Option D: Accept Current Approximation (Document Limitations)

**Approach**: Keep current implementation, document that numerator is approximate

**Current metrics meaning**:
- "Branches hit" ≈ Chez Scheme branch expressions executed
- "Coverage %" ≈ Scheme-level approximation of semantic coverage
- NOT true BranchId-level coverage

**Pros**:
- Already working
- Still useful signal

**Cons**:
- Not true dunham semantic coverage
- Numbers may be misleading

**Effort**: Minimal (documentation)

---

## 4. Recommended Approach

### Phase 1: Document Current Limitations (Immediate)
- Update README to clarify coverage metric meaning
- Distinguish "static analysis" (accurate) from "runtime coverage" (approximate)

### Phase 2: Implement Pattern Matching Heuristics (Short-term)
- Parse .ss file structure to find function boundaries
- Match --dumpcases %case blocks to Scheme case expressions
- Build approximate BranchId → line mapping

### Phase 3: Validate Against Manual Analysis (Medium-term)
- Create test cases with known BranchId coverage
- Compare heuristic results with ground truth
- Refine heuristics based on discrepancies

### Phase 4: Explore Compiler Integration (Long-term)
- Propose source map feature to Idris2 community
- Implement prototype if interest exists

---

## 5. Technical Details

### 5.1 Key Files in idris2-coverage

| File | Purpose | Key Functions |
|------|---------|---------------|
| `DumpcasesParser.idr` | Parse --dumpcases output | `parseDumpcasesFile`, `analyzeFunction` |
| `Collector.idr` | Parse .ss.html profiler | `parseBranchCoverage`, `extractSpansWithContent` |
| `Types.idr` | Data structures | `BranchId`, `BranchClass`, `AggregatedCoverage` |
| `UnifiedRunner.idr` | Test execution with coverage | `runTestsWithSemanticCoverage` |
| `SemanticCoverage.idr` | High-level API | `analyzeProjectWithHits` |

### 5.2 --dumpcases Output Format

```
{module}.{func} = [{args}] {body}

{body} ::= (%case {var} [{branches}] {default})
         | (%constcase {const} {body})
         | (%concase {ctor} {tag} {arity} {body})
         | (CRASH "{message}")
         | ...
```

### 5.3 .ss.html Span Format

```html
<span class=pc{N} title="line {L} char {C} count {hits}">{content}</span>
```

Where:
- `N` = 0-12 (heat level for coloring)
- `L` = line number in .ss file
- `C` = character position
- `hits` = execution count
- `content` = Scheme expression

---

## 6. Open Questions

1. **Does Idris2 preserve case order?** If --dumpcases and .ss have same order, mapping is trivial.

2. **How does inlining affect mapping?** Inlined functions may duplicate cases.

3. **Are there existing source map tools for Chez Scheme?** Could leverage existing work.

4. **Would upstream accept --emit-source-map flag?** Determines long-term viability of Option A.

---

## 7. References

- dunham's classification: Idris2 community discussion on CRASH semantics
- Eremondi-Kammar 2025: Semantic coverage formalization
- Chez Scheme profiler: https://cisco.github.io/ChezScheme/csug9.5/use.html#./use:h8
- Idris2 codegen: https://github.com/idris-lang/Idris2/tree/main/src/Compiler

---

## Appendix A: Current Code Path

```
User runs: idris2-cov pkgs/LazyCore

1. Main.runBranches (Main.idr:232)
   │
   ├── analyzeProjectFunctions (SemanticCoverage.idr:85)
   │   └── runDumpcasesDefault → parseDumpcasesFile
   │       → List CompiledFunction with BranchIds
   │
   ├── findTestModules (Main.idr:217)
   │   → ["Tests.AllTests"]
   │
   └── runTestsWithSemanticCoverage (UnifiedRunner.idr:289)
       │
       ├── Build test binary with --dumpcases
       │   → /tmp/idris2_dumpcases_test_*.txt
       │
       ├── Parse dumpcases → aggregateAnalysis
       │   → totalCanonical (DENOMINATOR)
       │
       ├── Run test binary (with Chez profiler)
       │   → .ss.html generated
       │
       └── parseBranchCoverage (Collector.idr:372)
           → List BranchPoint
           → length(filter hasHits) (NUMERATOR) ← MISMATCH HERE
```

---

*Document created: 2024-12-17*
*Status: Research Plan - Not Implemented*
