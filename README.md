# idris2-coverage

A pragmatic coverage tool for Idris2, built entirely on top of existing compiler outputs.

This tool makes **CI-friendly test coverage** feasible for Idris2 projects by
carefully distinguishing *type-proven unreachable code* from *genuinely reachable but untested code*,
without modifying the compiler or its coverage semantics.

---

## Motivation

Idris2 already has a strong notion of *coverage* and *totality* based on dependent types.
In theory, this means that many branches are **provably unreachable**.

In practice, however, this creates a tension when trying to use coverage in CI:

* Some branches can never execute (e.g. `void`, uninhabited patterns)
* Some branches are reachable but missing tests (real bugs)
* Some branches appear due to optimizer or compilation artifacts

Treating all of these uniformly makes **100% coverage either meaningless or unattainable**.

This project takes a deliberately conservative approach:

> **Trust Idris2’s notion of impossibility,
> but do not treat all compiler-emitted “CRASH” cases as equivalent.**

---

## What this tool does (and does not)

### ✅ What it does

* Consumes **existing Idris2 outputs only**

  * `idris2 --dumpcases`
  * Chez Scheme profiler (`.ss.html`)
* Classifies case branches into **practical categories**:

  * Canonical (reachable, should be tested)
  * Excluded (type-proven unreachable, e.g. `void`)
  * Bug-like (reachable but missing cases, e.g. `partial`)
  * Non-semantic (optimizer artifacts)
  * Unknown (conservatively reported, never excluded)
* Computes coverage **only over canonical, reachable branches**
* Produces **transparent reports** suitable for CI

### ❌ What it does *not* do

* It does **not** modify Idris2
* It does **not** redefine coverage or totality
* It does **not** attempt to “fix” the compiler
* It does **not** assume all `CRASH` nodes are semantically meaningful

This is a **downstream tooling experiment**, not a language change.

---

## Core idea

Coverage is measured in two stages:

```
Static (semantic) analysis:
  --dumpcases
    → classify branches
    → identify canonical (reachable) cases

Dynamic (runtime) analysis:
  Chez Scheme profiler
    → map execution hits to canonical cases

Final coverage:
  executed_canonical / total_canonical
```

Only branches that are *both* semantically reachable *and* executable
are counted toward the denominator.

---

## CRASH classification (pragmatic)

The compiler may emit `CRASH` nodes for different reasons.
This tool distinguishes them conservatively based on their origin:

| Origin                   | Example                | Treatment                |
| ------------------------ | ---------------------- | ------------------------ |
| Uninhabited / No-clauses | `void`                 | Excluded                 |
| Partial functions        | `Unhandled input …`    | Reported as bug          |
| Optimizer artifacts      | `Nat case not covered` | Non-semantic             |
| Unknown / other          | anything else          | Reported, never excluded |

Unknown cases are **never** silently dropped.

---

## Example

```idris
safeHead : NonEmpty a -> a
safeHead (x :: _) = x
```

Idris2 proves that the empty case is impossible.
This tool excludes that branch from coverage,
allowing meaningful coverage metrics without weakening correctness.

---

## Output

The tool reports:

* Total canonical branches
* Executed canonical branches
* Excluded branches (with reasons)
* Bug-like missing branches
* Non-semantic artifacts
* Unknown cases (explicitly listed)

Coverage percentages are always accompanied by a breakdown,
so users can judge trustworthiness.

---

## Usage

```bash
idris2-coverage myproject.ipkg \
  --profile-html path/to/profile.ss.html
```

Exit codes are CI-friendly:

* `0` — no missing reachable cases
* `1` — reachable but untested cases found
* `2` — analysis error (report still produced)

---

## Design principles

* **Conservative by default**
  When unsure, report — never exclude.
* **Downstream only**
  Compiler behavior is observed, not changed.
* **Transparent accounting**
  Every exclusion is justified and visible.
* **Pragmatic correctness**
  Optimized for real-world CI usage.

---

## Status

This tool is production-ready for CI usage,
but intentionally scoped.

Future improvements may include better origin tagging
or additional report formats,
but correctness is prioritized over completeness.

---

## Feedback

Feedback is very welcome, especially regarding:

* CRASH classification edge cases
* CI integration experiences
* Reporting clarity

This project aims to complement Idris2,
not redefine it.

---

## License

MIT
