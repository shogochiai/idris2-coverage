# Development Guide

## Version Management

Current version: `0.1.0` (defined in [src/Main.idr:128](../src/Main.idr#L128))

### Version Update Checklist

When releasing a new version:

1. **Update version string** in `src/Main.idr`:
   ```idris
   versionText : String
   versionText = "idris2-coverage X.Y.Z"
   ```

2. **Rebuild**:
   ```bash
   idris2 --build idris2-coverage.ipkg
   ```

3. **Verify**:
   ```bash
   ./build/exec/idris2-cov --version
   ```

4. **Commit & tag**:
   ```bash
   git add src/Main.idr
   git commit -m "release: vX.Y.Z"
   git tag vX.Y.Z
   git push && git push --tags
   ```

## Build Commands

```bash
# Build the library and CLI
idris2 --build idris2-coverage.ipkg

# Install as package (for use as dependency)
idris2 --install idris2-coverage.ipkg

# Clean build artifacts
rm -rf build/
```

## Project Structure

```
src/
├── Main.idr                    # CLI entry point, version string
└── Coverage/
    ├── Types.idr               # Core types (CaseKind, SemanticCoverage)
    ├── DumpcasesParser.idr     # --dumpcases output parser, ExclusionConfig
    ├── Exclusions.idr          # Load patterns from exclusions/ directory
    ├── TestCoverage.idr        # High-level coverage API, target filtering
    ├── UnifiedRunner.idr       # Test execution with profiling
    ├── Config.idr              # .idris2-cov.toml parser
    ├── TestRunner.idr          # Test discovery utilities
    ├── Aggregator.idr          # Coverage aggregation
    ├── Report.idr              # Output formatting (JSON, text)
    └── Tests/
        └── AllTests.idr        # Unit tests
exclusions/
├── README.md                   # Exclusion patterns documentation
├── base.txt                    # Patterns common to ALL Idris2 versions
└── 0.8.0.txt                   # Patterns specific to Idris2 0.8.0
```

## Adding a New Module

1. Create file in `src/Coverage/NewModule.idr`
2. Add to `idris2-coverage.ipkg`:
   ```
   modules = ..., Coverage.NewModule
   ```
3. Import in relevant files

## Configuration File

Projects can use `.idris2-cov.toml` to customize exclusions:

```toml
[exclusions]
# Exclude modules by prefix (e.g., internal libraries)
module_prefixes = ["Coverage.", "Internal."]

# Additional packages to exclude (beyond ipkg depends)
packages = ["mylib"]
```

The tool automatically:
- Reads `depends` from the project's `.ipkg`
- Merges with config's `packages` list
- Excludes standard library modules (`Prelude.*`, `System.*`, etc.)

## Testing

```bash
# Run self-coverage analysis
./build/exec/idris2-cov .

# JSON output with top 20 targets
./build/exec/idris2-cov --json --top 20 .
```

## Key Files for Common Tasks

| Task | File |
|------|------|
| Add CLI option | [src/Main.idr](../src/Main.idr) `parseArgs` |
| Add exclusion pattern | [src/Coverage/DumpcasesParser.idr](../src/Coverage/DumpcasesParser.idr) |
| Modify JSON output | [src/Coverage/Report.idr](../src/Coverage/Report.idr) |
| Change target filtering | [src/Coverage/TestCoverage.idr](../src/Coverage/TestCoverage.idr) |
| Config file parsing | [src/Coverage/Config.idr](../src/Coverage/Config.idr) |

## Semantic Versioning

- **PATCH** (0.0.x): Bug fixes, doc updates
- **MINOR** (0.x.0): New features, backward compatible
- **MAJOR** (x.0.0): Breaking changes to CLI or API

---

## Idris2 Version Tracking (Contributor Guide)

### Why This Matters

The exclusion patterns (compiler-generated functions, standard library prefixes, etc.) are **Idris2 version-dependent**. When Idris2 releases a new patch version:
- New compiler-generated patterns may appear (`{csegen:N}`, `{eta:N}`, etc.)
- Standard library module names may change
- New optimizer artifacts may be introduced

**If we don't track these, users will see "leaks" in their coverage reports.**

**Your codebase and report keeps this project fresh. We need enough amount of eyes.**

### Tracking Workflow

When a new Idris2 version is released:

#### 1. Detect New Patterns

```bash
# Update Idris2 to new version
pack install-app idris2-0.X.Y

# Rebuild idris2-coverage with new compiler
idris2 --build idris2-coverage.ipkg

# Run wide analysis on a large project
./build/exec/idris2-cov --json --top 1000 /path/to/large/project > analysis.json

# Extract potential leaks (non-user functions in targets)
cat analysis.json | jq '.high_impact_targets[].funcName' | \
  grep -E '^"(\{|_builtin|prim__|Prelude\.|Data\.|System\.|Control\.)' | \
  sort -u
```

#### 2. Identify New Exclusion Patterns

Look for:
- New `{xyz:N}` patterns (compiler MN names)
- New `prim__*` primitives
- New standard library module prefixes
- New type constructor patterns (ending with `.`)

#### 3. Update Exclusion Logic

Edit [src/Coverage/DumpcasesParser.idr](../src/Coverage/DumpcasesParser.idr):

```idris
-- Add new patterns to appropriate functions:

isCompilerGenerated : String -> Bool
isCompilerGenerated name =
     isPrefixOf "{" name           -- MN names
  || isPrefixOf "_builtin." name   -- Builtins
  || isPrefixOf "prim__" name      -- Primitives
  -- ADD NEW PATTERNS HERE

isStandardLibraryFunction : String -> Bool
isStandardLibraryFunction name =
     isPrefixOf "Prelude." name
  || isPrefixOf "Data." name
  -- ADD NEW MODULE PREFIXES HERE
```

#### 4. Document and Release

1. Update [docs/compiler-generated-functions.md](./compiler-generated-functions.md) with new patterns
2. Add entry to changelog noting Idris2 version compatibility
3. Release new idris2-coverage version

### Compatibility Matrix

| idris2-coverage | Idris2 Version | Notes |
|-----------------|----------------|-------|
| 0.1.x           | 0.7.0          | Initial release |

### Scripts

Two scripts are provided in `scripts/`:

#### `detect-leaks.sh` - Check for Leaks

```bash
# Check your project for exclusion leaks
./scripts/detect-leaks.sh /path/to/project 1000

# Output:
# Analyzing /path/to/project with top 1000 targets...
# No leaks detected.
#   OR
# LEAKS DETECTED:
#   - {newpattern:42}
#   - SomeNew.Module.func
```

#### `report-leak.sh` - Auto-Create PR

If leaks are found, contributors can auto-create a PR:

```bash
# Fork and clone idris2-coverage first, then:
./scripts/report-leak.sh /path/to/project 1000

# This will:
# 1. Detect leaks
# 2. Create a branch with leak report
# 3. Open a PR via `gh` CLI
```

**Prerequisites**: `gh` CLI installed and authenticated.

### CI Integration (Future)

Ideally, set up GitHub Actions to:
1. Watch for new Idris2 releases
2. Automatically run leak detection
3. Open an issue if leaks are found

```yaml
# .github/workflows/idris2-compat.yml (example)
name: Idris2 Compatibility Check
on:
  schedule:
    - cron: '0 0 * * 0'  # Weekly
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install latest Idris2
        run: pack install-app idris2
      - name: Build
        run: idris2 --build idris2-coverage.ipkg
      - name: Detect Leaks
        run: ./scripts/detect-leaks.sh . 1000
```
