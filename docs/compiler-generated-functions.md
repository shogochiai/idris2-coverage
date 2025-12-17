# Compiler-Generated Functions

## Overview

Idris2's compiler generates internal functions during optimization, such as:
- `{csegen:N}` - Common subexpression generation
- Other `{...}` prefixed names

These are **not user code** and should be excluded from coverage targets.

## Current Handling

### High Impact Targets (v1.0)

Compiler-generated functions are **filtered out** from `high_impact_targets` output:

```idris
isCompilerGenerated : String -> Bool
isCompilerGenerated name = isPrefixOf "{" name
```

This means:
- They still appear in `--dumpcases` output
- They still count toward `total_canonical` in summary
- But they are **not listed** as targets to fix

### Why Not Exclude from Denominator?

Unlike `CrashNoClauses` (void/absurd patterns), compiler-generated functions:
1. Are technically reachable at runtime
2. Could theoretically be tested (by exercising the code that uses them)
3. Are not "impossible" in the type-theoretic sense

Therefore, excluding them from the denominator would be philosophically incorrect.

## Future Considerations

If the community consensus is that `{csegen:*}` should be excluded from coverage entirely:
1. Add a new `BranchClass`: `BCCompilerGenerated`
2. Exclude from denominator alongside `BCExcludedNoClauses`
3. Update the pragmatic coverage formula

For now, the conservative approach is to filter them from *targets* but keep them in *totals*.
