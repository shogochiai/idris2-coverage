# idris2-coverage

A pragmatic, proof-aware test coverage tool for Idris2.

This tool makes **CI-friendly coverage reporting** feasible for Idris2 projects
by respecting dependent types, proofs, and uninhabited cases,
rather than counting them naively.

It is implemented entirely as a **downstream tool** on top of existing
compiler outputs, and does not modify Idris2 itself.

---

## Motivation

In dependently typed languages, naive test coverage is often misleading.

Many execution paths are *provably unreachable* due to types and proofs,
while others appear only as artifacts of compilation or optimization.
Treating all branches uniformly makes coverage either meaningless
or impossible to satisfy in practice.

At the same time, real-world Idris2 projects still need:

- CI signals for untested, reachable code
- Regression protection as code evolves
- Practical tooling that integrates with existing workflows

This project exists to bridge that gap:

> **Make test coverage meaningful again,  
> by counting only what can actually happen.**

---

## What this tool does

### ✔ What it does

- Consumes **existing Idris2 outputs only**
  - `idris2 --dumpcases`
  - Chez Scheme profiler output (`.ss.html`)
- Distinguishes between different kinds of branches:
  - *Semantically reachable* branches that should be tested
  - *Type-proven unreachable* branches (e.g. `void`, uninhabited patterns)
  - *Genuinely missing* cases (e.g. `partial` functions)
  - *Non-semantic artifacts* introduced by compilation or optimization
- Computes coverage **only over reachable, canonical cases**
- Produces **transparent reports** suitable for CI usage

### ✘ What it does not do

- It does **not** change Idris2’s coverage checker
- It does **not** redefine totality or impossibility
- It does **not** assume all compiler-emitted `CRASH` nodes mean the same thing
- It does **not** hide uncertainty — unknown cases are always reported

This is a **downstream, proof-aware tooling experiment**, not a language change.

---

## Core idea

Coverage is computed in two layers:

```

Static (semantic) layer:
idris2 --dumpcases
→ classify branches
→ identify canonical (reachable) cases

Dynamic (runtime) layer:
Chez Scheme profiler (.ss.html)
→ map execution hits to canonical cases

Final coverage:
executed_canonical / total_canonical

````

Only branches that are both *semantically reachable*
and *actually executable* are counted.

---

## CRASH classification (conservative)

The compiler may emit `CRASH` nodes for multiple reasons.
This tool classifies them conservatively based on their origin:

| Category | Example | Treatment |
|--------|--------|-----------|
| Uninhabited / No-clauses | `void` | Excluded |
| Partial / missing cases | `Unhandled input ...` | Reported as bugs |
| Optimizer artifacts | `Nat case not covered` | Non-semantic |
| Unknown | anything else | Reported, never excluded |

Unknown cases are **never silently dropped**.

---

## Example

```idris
safeHead : NonEmpty a -> a
safeHead (x :: _) = x
````

The empty case is provably impossible.
This tool excludes that branch from coverage,
allowing meaningful metrics without weakening correctness.

---

## Output

The tool reports:

* Total canonical (reachable) branches
* Executed canonical branches
* Excluded branches (with reasons)
* Bug-like missing cases
* Non-semantic artifacts
* Unknown cases (explicitly listed)

Coverage percentages are always accompanied by a breakdown.

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

* **Proof-aware by default**
  Respect uninhabited cases and impossibility.
* **Conservative accounting**
  When unsure, report — never exclude.
* **Downstream only**
  Observe compiler behavior; do not modify it.
* **Pragmatic correctness**
  Optimized for real-world CI usage.

---

## Status

This tool is production-ready for CI usage,
with intentionally conservative scope.

Future improvements may refine classification or reporting,
but correctness and transparency take priority over completeness.

---

## Versioning

This project follows 0.x versioning.
Breaking changes may occur between minor versions.

---

## Maintenance policy

This is a small, pragmatic tool developed primarily for the author's own use.
Issues and pull requests are welcome, but maintenance is best-effort.

---

## Feedback

Feedback is very welcome, especially regarding:

* Edge cases in CRASH classification
* CI integration experiences
* Report clarity and usability

This project aims to complement Idris2,
not redefine it.

---

## License

MIT
