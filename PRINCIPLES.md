# AOS Principles

**Status:** Canonical
**Role:** Stable constraints for product, specification, and implementation
decisions

## How to use these principles

Every proposed AOS capability must state how it complies with the principles
below. A roadmap item, implementation convenience, or extension request cannot
silently override them.

Changing a principle requires an accepted Architecture Decision Record (ADR)
that explains the reason and consequences and updates this document in the same
change. If a design cannot comply and no such ADR exists, the design is not part
of AOS Core.

## P1 — The repository is the durable source of project truth

Project intelligence that must survive sessions belongs with the managed
repository or in a repository-declared system of record.

This requires durable, inspectable data and explicit links to any external
authority. Chat history, local model memory, and private prompts cannot be the
only source of an authoritative decision.

## P2 — Explicit state is preferred over inferred state

AOS distinguishes declared or observed state from interpretation. State must
identify its source, time, and confidence or authority where relevant.

AOS must not present an assumption, stale observation, or generated summary as
confirmed current state.

## P3 — Protocol is preferred over prompt

Repeatable work is governed by versioned protocols with named inputs, outputs,
checks, and failure behavior.

Prompts may help a tool perform work, but a hidden prompt cannot define the
project contract or replace a protocol.

## P4 — Knowledge is preferred over chat history

Reusable project understanding is captured as structured, attributable
knowledge. Conversation may be evidence, but it is not durable knowledge until
it is reviewed and synchronized through the project model.

AOS must not require a specific conversation to reconstruct a project decision.

## P5 — Humans retain accountable authority

AOS assists decision-making and may execute work within granted capabilities,
but governance defines who can authorize consequential actions.

AI providers, runtimes, and extensions must not grant themselves authority or
bypass approval boundaries.

## P6 — Every authoritative fact has provenance

Knowledge, state, decisions, and generated outputs must be traceable to their
source, producer, version, and relevant time.

Unverifiable information may be retained as a proposal or observation, but not
promoted silently to authoritative truth.

## P7 — No silent mutation

AOS must explain intended writes, their ownership, and expected impact before
performing them. Mutating operations must be auditable, fail safely, and provide
a recovery or reconciliation path.

AOS must not overwrite user-owned project content merely to make the project
match an assumed model.

## P8 — Deterministic and reproducible behavior first

Given the same versioned inputs, configuration, and declared environment,
contract-level behavior should be reproducible.

Non-deterministic providers may assist execution, but their outputs must pass
deterministic validation before becoming authoritative.

## P9 — Retrieve the minimum sufficient context

AOS should provide the context needed for a task and an explicit path to request
more. It should not load the entire project by default or hide why information
was selected.

Context selection must preserve provenance and must not omit known blocking
constraints.

## P10 — Remain tool- and provider-neutral

Core semantics and contracts must not depend on a particular model, agent, IDE,
programming language, source host, or cloud provider.

Provider-specific behavior belongs behind versioned adapters or extensions.

## P11 — Keep the core minimal and extensions constrained

Core contains only semantics and capabilities required for interoperable project
intelligence. Optional domain, language, framework, and provider behavior belongs
in extensions.

Extensions must use published contracts and cannot redefine core concepts,
bypass governance, or directly claim project authority.

## P12 — Correct first, simple first, verified first, scale later

AOS prioritizes semantic correctness, understandable local operation, and
evidence-backed behavior before optimization or distribution.

Complex infrastructure requires a measured bottleneck or reliability need. A
distributed runtime is not a substitute for a correct local model.

## Decision rule

When principles appear to conflict, choose the interpretation that best
preserves project truth, human authority, reversibility, and auditability. Record
any material tradeoff in an ADR before implementation.
