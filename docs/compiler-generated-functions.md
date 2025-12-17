# Compiler-Generated Functions

## Overview

Idris2's compiler generates internal functions during compilation and optimization.
These are **not user code** and should be excluded from coverage targets.

## Comprehensive Pattern Reference

### Machine-Generated Names (`MN` type)

Format: `{prefix:N}` where N is an incrementing index.

| Prefix | Description | Source Module |
|--------|-------------|---------------|
| `csegen` | Common Subexpression Elimination | `Compiler/Opts/CSE.idr` |
| `act` | Lambda lift actions | `Compiler/LambdaLift.idr` |
| `arg` | Builtin operation arguments | `Compiler/CompileExpr.idr` |
| `eta` | Eta expansion variables | `Compiler/CompileExpr.idr` |
| `eff` | Effect bindings (newtype case) | `Compiler/CompileExpr.idr` |
| `ext` | External function inlining | `Compiler/Inline.idr` |
| `bind` | Bind expression variables | (internal) |
| `clam` | Case lambda variables | (internal) |
| `lamc` | Lambda case variables | (internal) |
| `e` | Generic expression variables | (internal) |
| `i_con` | Interface constraint arguments | (internal) |
| `world` | IO world token threading | (internal) |
| `x` | Generic variable binding | `Compiler/CompileExpr.idr` |
| `_` | Wildcard/unused variables | `Core/Name.idr` |

### Special Names

| Pattern | Description |
|---------|-------------|
| `{__mainExpression:0}` | Program entry point |
| `{__leftTupleSection:N}` | Left tuple section syntax |
| `{__infixTupleSection:N}` | Infix tuple section syntax |

### Builtin Constructors

| Pattern | Description |
|---------|-------------|
| `_builtin.NIL` | Empty list `[]` |
| `_builtin.CONS` | List cons `(::)` |
| `_builtin.NOTHING` | `Nothing` constructor |
| `_builtin.JUST` | `Just` constructor |

### Primitive Operations

| Pattern | Description |
|---------|-------------|
| `prim__*` | Primitive operations (e.g., `prim__sub_Integer`) |

## Current Handling

### High Impact Targets Filter

Compiler-generated functions are **filtered out** from `high_impact_targets`:

```idris
isCompilerGenerated : String -> Bool
isCompilerGenerated name =
     isPrefixOf "{" name
  || isPrefixOf "_builtin." name
  || isPrefixOf "prim__" name
```

This means:
- They still appear in `--dumpcases` output
- They still count toward `total_canonical` in summary
- But they are **not listed** as actionable targets

### Why Not Exclude from Denominator?

Unlike `CrashNoClauses` (void/absurd patterns), compiler-generated functions:
1. Are technically reachable at runtime
2. Could theoretically be tested (by exercising the code that uses them)
3. Are not "impossible" in the type-theoretic sense

Therefore, excluding them from the denominator would be philosophically incorrect.

## Future Considerations

If the community consensus is that compiler-generated functions should be excluded entirely:
1. Add a new `BranchClass`: `BCCompilerGenerated`
2. Exclude from denominator alongside `BCExcludedNoClauses`
3. Update the pragmatic coverage formula

For now, the conservative approach is to filter them from *targets* but keep them in *totals*.

## References

- [Idris2 Core/Name.idr](https://github.com/idris-lang/Idris2/blob/main/src/Core/Name.idr) - MN type definition
- [Idris2 Compiler/Opts/CSE.idr](https://github.com/idris-lang/Idris2/blob/main/src/Compiler/Opts/CSE.idr) - CSE optimization
- [Idris2 Compiler/CompileExpr.idr](https://github.com/idris-lang/Idris2/blob/main/src/Compiler/CompileExpr.idr) - Expression compilation
