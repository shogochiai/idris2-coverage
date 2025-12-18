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
    ├── TestCoverage.idr        # High-level coverage API, target filtering
    ├── UnifiedRunner.idr       # Test execution with profiling
    ├── Config.idr              # .idris2-cov.toml parser
    ├── TestRunner.idr          # Test discovery utilities
    ├── Aggregator.idr          # Coverage aggregation
    ├── Report.idr              # Output formatting (JSON, text)
    └── Tests/
        └── AllTests.idr        # Unit tests
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
