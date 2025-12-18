# idris2-coverage

**Type-aware, per-function branch coverage for Idris 2.**

idris2-coverage is a coverage analysis tool designed specifically for **dependently typed languages**, starting with Idris 2. It measures *what actually matters* in such languages: **which type-driven branches of which functions have been exercised by your tests**.

This is not line coverage. It is not path coverage in the traditional sense. And it is not a probabilistic heuristic.

It is **coverage over a finite, type-constrained semantic space**, made observable.

---

## Why idris2-coverage exists

In most mainstream languages, coverage metrics eventually collapse under their own weight:

* Branches explode combinatorially with input size and runtime state.
* 100% coverage is either meaningless or unattainable.
* Uncovered areas do not tell you *where to think next*.

Dependent types fundamentally change this situation.

In Idris 2:

* Types *eliminate* impossible states.
* Pattern matching induces a **finite case tree** per function.
* The compiler can enumerate this space precisely.

idris2-coverage is built on a simple but powerful idea:

> **If the type system already defines the space of meaningful behavior, coverage should be measured *over that space*, and nowhere else.**

---

## What does it measure?

At a high level, idris2-coverage computes the following ratio:

> **Numerator**: Branches that were *actually executed* during test runs
> **Denominator**: Branches that *should reasonably be tested by the user*

Both sides are computed precisely, not heuristically.

### The denominator: meaningful branches only

The denominator is constructed from Idris 2's `--dumpcases` output, which enumerates the compiler’s **canonical case tree** for each function.

However, not everything the compiler emits should count as user responsibility.

idris2-coverage systematically excludes:

* **Unreachable / absurd branches** (provably impossible by types)
* **Optimizer artifacts** (e.g. backend-induced cases such as `Nat` lowering)
* **Compiler-generated helper functions**
* **Standard library code**
* **Test modules and test-only helpers**

These exclusions are *explicit*, versioned, and auditable.

The result is a denominator that represents:

> **“All type-valid branches a user could and should test.”**

### The numerator: what actually happened

On the numerator side, idris2-coverage relies on the **Chez Scheme profiler**, used by the Idris 2 Chez backend.

During test execution:

* Every executed branch is recorded by the runtime profiler.
* The profiler output is parsed deterministically.
* Runtime hits are mapped back to Idris-level functions and branches.

No static guessing. No symbolic approximation.

> **Only observed execution counts.**

---

## Per-function coverage (this is the key)

Coverage is computed **per function**, not just globally.

This enables something that most coverage tools cannot offer:

> **You can sort functions by “coverage impact” and immediately see where your attention matters most.**

Instead of asking:

* “How do I push the total percentage up?”

You can ask:

* “Which function represents the largest untested semantic gap?”

This turns coverage from a vanity metric into a **thinking aid**.

---

## Why this only works in a dependently typed language

In languages like Rust, C++, or Java:

* The state space is open-ended.
* Many branches are runtime-accidental rather than semantically essential.
* Coverage metrics inevitably reward mechanical test inflation.

In Idris 2:

* The type system already *solves* most combinatorial explosion.
* Pattern matching over indexed types yields **finite, inspectable spaces**.
* Impossible cases are first-class and explicit.

idris2-coverage is not fighting the language.

> **It is finishing the job the type system started.**

---

## For Idris experts

idris2-coverage gives you:

* A concrete bridge between **type-level exhaustiveness** and **runtime evidence**
* A practical interpretation of “semantic coverage”
* A way to reason about testing that respects dependent pattern matching

It pairs naturally with:

* Property-based testing
* Type-narrowed fuzzing
* Spec–Test–Implementation parity workflows

---

## For non-Idris users / Vibe Coders

You do **not** need to fully understand Idris 2 to benefit from this tool.

You can treat idris2-coverage as:

* A black box that tells you *which functions still need thought*
* A guardrail that prevents infinite test-writing
* A guide that keeps your energy focused

You write tests. You run the tool. It tells you where the real gaps are.

> **No coverage golf. No combinatorial despair.**

Just direction.

---

## What this is *not*

* Not line coverage
* Not statement coverage
* Not traditional path coverage
* Not a replacement for thinking

It is a **semantic instrument**, not a checkbox generator.

---

## One-sentence summary

> **idris2-coverage measures how much of the *type-defined meaning* of your program has actually been exercised — and tells you exactly where to think next.**

---

## Status

* Actively used on real Idris 2 codebases
* Designed to evolve alongside Idris 2 compiler semantics
* Open to collaboration and scrutiny

If dependent types are the future of reliable software, this is what coverage looks like in that future.
