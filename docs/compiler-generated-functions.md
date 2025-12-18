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

### Standard Library Modules (External Dependencies)

These modules are from Idris2's `base` or `contrib` packages, not user code.
They should be **excluded from coverage targets** since you cannot test their internals.

| Module Prefix | Description |
|---------------|-------------|
| `Prelude.` | Core prelude (Show, Types, etc.) |
| `Data.` | Data structures (String, List, etc.) |
| `System.` | System interaction (File, Directory, Clock, etc.) |
| `Control.` | Control flow abstractions |
| `Decidable.` | Decidability proofs |
| `Language.` | Language reflection |
| `Debug.` | Debug utilities |

Examples from real analysis:
- `System.File.ReadWrite.readLinesOnto` (21 branches)
- `System.Directory.nextDirEntry` (19 branches)
- `Data.String.with block in parsePositive,parsePosTrimmed` (18 branches)
- `Prelude.Show.showLitChar` (14 branches)
- `Prelude.Types.rangeFromTo` (13 branches)

### Type Constructors (Non-Function Entries)

Functions ending with `.` are **data constructor case trees**, not user-defined logic.
The trailing dot indicates auto-generated ADT constructor handling.

| Pattern | Example | Description |
|---------|---------|-------------|
| `Module.Type.` | `Shared.Types.Ask.` | Constructor for `Ask` type |
| `Module.Type.` | `Shared.Types.Ledger.` | Constructor for `Ledger` type |
| `Module.Type.` | `Shared.Signal.Policy.` | Constructor for `Policy` type |
| `Module.Type.` | `Coverage.DumpcasesParser.` | Constructor cases |

These are compiler-generated case trees for pattern matching on ADTs.

## Current Handling

### High Impact Targets Filter

Compiler-generated functions are **filtered out** from `high_impact_targets`:

```idris
isCompilerGenerated : String -> Bool
isCompilerGenerated name =
     isPrefixOf "{" name           -- MN names: {csegen:N}, {eta:N}, etc.
  || isPrefixOf "_builtin." name   -- Builtin constructors
  || isPrefixOf "prim__" name      -- Primitive operations

isStandardLibrary : String -> Bool
isStandardLibrary name =
     isPrefixOf "Prelude." name
  || isPrefixOf "Data." name
  || isPrefixOf "System." name
  || isPrefixOf "Control." name
  || isPrefixOf "Decidable." name
  || isPrefixOf "Language." name
  || isPrefixOf "Debug." name

isTypeConstructor : String -> Bool
isTypeConstructor name =
  isSuffixOf "." name && not (isPrefixOf "{" name)
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
