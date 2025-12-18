# Accurate Per-Function Runtime Hit Research Plan

## Current State

### What Works (Legacy)
- **Proportional approximation**: Global `executed/canonical` ratio applied uniformly to all functions
- Example: If project has 26% coverage, each function is assumed to have ~26% of its branches executed
- This is inaccurate but provides a reasonable approximation

### What We Added (Disabled)
- `FunctionRuntimeHit` type in `Types.idr`
- `matchAllFunctionsWithCoverage` in `Collector.idr`
- `runTestsWithFunctionHits` in `UnifiedRunner.idr`
- `topKTargetsFromRuntimeHits*` APIs in `TestCoverage.idr`

### Why It's Disabled
The matching logic produces incorrect results:
- All functions show `executedCount == canonicalCount` (100% coverage)
- Root cause: `parseAnnotatedHtml` and `groupByLine` don't differentiate per-function

## Research Questions

### RQ1: How does Chez Scheme profiler output map to Idris functions?

**Sub-questions:**
1. What is the exact format of `.ss.html` profiler output?
2. How are expression hit counts encoded in the HTML?
3. How do Scheme function boundaries correspond to line numbers?

**Investigation approach:**
```bash
# Generate sample profiler output
./build/exec/idris2-cov . 2>&1
# Examine the .ss.html file before cleanup
cat temp-test-*.ss.html | head -100
```

### RQ2: How to map Idris function names to Scheme function names?

**Sub-questions:**
1. What is the Idris → Scheme name mangling scheme?
   - `Module.func` → `Module-func` or `ModuleC-45func`?
2. How are nested functions named in Scheme?
3. How are case blocks and where clauses named?

**Current implementation:**
```idris
idrisFuncToSchemePattern : String -> String
idrisFuncToSchemePattern idrisName =
  fastConcat $ intersperse "-" $ forget $ split (== '.') idrisName
```

**Known issue:** This is too simplistic. Need to understand actual mangling.

### RQ3: How to extract per-function line ranges from `.ss` files?

**Sub-questions:**
1. How are Scheme function definitions structured in `.ss`?
2. Can we parse `(define ...)` forms to get function boundaries?
3. How do we handle inlined functions?

**Current implementation:**
```idris
parseSchemeDefs : String -> List (String, Nat)
```

**Known issue:** May not be parsing correctly or returning useful data.

### RQ4: Alternative approach - use `--dumpcases` output directly?

**Sub-questions:**
1. Does `--dumpcases` provide line number information?
2. Can we correlate case trees to profiler hit locations?
3. Is there a more direct mapping than going through `.ss`?

## Research Approach

### Phase 1: Data Collection (1-2 hours)

1. **Capture raw profiler output**
   ```bash
   # Modify UnifiedRunner.idr to NOT delete temp files
   # Run and examine:
   ls -la *.ss.html *.ss
   cat temp-test-*.ss.html > /tmp/sample-profiler.html
   cat build/exec/temp-test-*_app/*.ss > /tmp/sample-scheme.ss
   ```

2. **Document profiler format**
   - HTML structure of `.ss.html`
   - How hit counts are represented
   - Line number encoding

3. **Document Scheme structure**
   - Function definition syntax
   - Name mangling examples
   - Nested function handling

### Phase 2: Pattern Analysis (1-2 hours)

1. **Map known Idris functions to Scheme names**
   - Pick 5-10 functions from idris2-coverage
   - Find their Scheme equivalents manually
   - Document the transformation rules

2. **Identify line range boundaries**
   - For each mapped function, identify start/end lines
   - Check if profiler data falls within expected ranges

3. **Validate current parsing**
   - Check output of `parseAnnotatedHtml`
   - Check output of `groupByLine`
   - Check output of `parseSchemeDefs`

### Phase 3: Fix Implementation (2-4 hours)

Based on findings, fix one of:

**Option A: Fix `.ss.html` parsing**
- Improve `parseAnnotatedHtml` to extract per-expression hits correctly
- Improve `groupByLine` to aggregate properly

**Option B: Fix function matching**
- Improve `idrisFuncToSchemePattern` for correct name mangling
- Improve `parseSchemeDefs` to extract function boundaries

**Option C: Alternative data source**
- Use `--dumpcases` line info if available
- Use different profiler output format

### Phase 4: Validation (1 hour)

1. Enable `FunctionRuntimeHit` in `Main.idr`
2. Run on idris2-coverage itself
3. Verify targets have varying `executedCount` values
4. Compare severity rankings with legacy approach

## Success Criteria

1. **Accuracy**: `executedCount` varies meaningfully across functions
2. **Consistency**: Same function shows similar coverage across runs
3. **Sanity**: High-severity targets are genuinely untested functions
4. **Performance**: No significant slowdown from per-function analysis

## Files to Modify

| File | Purpose |
|------|---------|
| `Collector.idr` | Fix `parseAnnotatedHtml`, `groupByLine`, `parseSchemeDefs` |
| `Collector.idr` | Fix `matchFunctionWithCoverage` logic |
| `Main.idr` | Enable `FunctionRuntimeHit` usage (remove `pure Nothing`) |

## Related Documentation

- Chez Scheme profiler: https://cisco.github.io/ChezScheme/csug9.5/debug.html
- Idris2 codegen: https://idris2.readthedocs.io/en/latest/backends/
- Current implementation: `src/Coverage/Collector.idr:469-571`

## Notes

The type infrastructure (`FunctionRuntimeHit`, APIs, etc.) is complete and tested.
Only the data extraction/matching logic needs fixing.

Once fixed, both CLI and Library API will automatically benefit from accurate per-function severity calculation.
