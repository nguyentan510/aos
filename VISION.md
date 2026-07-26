# AOS Vision

**Status:** Canonical
**Product:** AOS — Project Intelligence Operating System

## Mission

Make every software repository capable of carrying the durable intelligence
needed for humans and AI-assisted tools to understand, change, and govern the
project safely.

## Vision

AOS aims to become an open, tool-neutral standard for project intelligence in
AI-assisted software engineering.

A project using AOS should not depend on one chat history, agent, model, IDE, or
vendor to explain what the project is, why it is designed that way, what state
it is in, what work is permitted, or how a change is verified. That intelligence
should remain with the project and survive changes in people and tools.

## Problem space

Software repositories normally store source code but leave important project
knowledge fragmented across conversations, issue trackers, undocumented
assumptions, and individual memory. AI-assisted development amplifies this
problem because tools operate with partial context and may:

- forget decisions between sessions;
- confuse historical intent with current truth;
- infer state from incomplete evidence;
- retrieve excessive or irrelevant context;
- duplicate or contradict architectural decisions;
- bypass project-specific review and quality rules; or
- produce changes that cannot be explained after the session ends.

The missing capability is not another code generator. It is a stable layer that
models project identity, knowledge, state, work, protocols, and governance and
makes those concepts available through versioned, inspectable interfaces.

## Target users

### Project owners

Need reliable project truth, explicit authority, and evidence that work follows
the intended architecture and quality rules.

### Contributors

Need fast onboarding, bounded context, current state, and an understandable path
from requested work to accepted change.

### AI and development-tool providers

Need a provider-neutral way to retrieve relevant project intelligence and
participate in governed workflows without owning project truth.

### AOS maintainers and extension authors

Need a stable reference model and versioned contracts that allow the ecosystem
to evolve without weakening the core.

## Product goals

### G1 — Repository-native project intelligence

The repository carries the durable information required to understand and
govern the project.

### G2 — Explicit and attributable truth

Knowledge and state have clear meaning, provenance, ownership, and lifecycle.

### G3 — Protocol-driven work

Work follows explicit, versioned protocols rather than relying on hidden prompts
or tool-specific conventions.

### G4 — Human-governed automation

Automation can assist or execute authorized work, but authority remains explicit
and accountable to project governance.

### G5 — Progressive context

Humans and tools retrieve the minimum sufficient project context for the task,
with a path to request more evidence when needed.

### G6 — Open and extensible interoperability

AOS remains independent of a specific language, framework, AI provider, editor,
or deployment platform. Optional capabilities integrate through versioned
extension contracts.

## Non-goals

AOS does not aim to:

- build or host a foundation model;
- become a general-purpose coding agent;
- replace Git, an IDE, CI/CD, issue tracking, or documentation systems;
- own the business logic of a managed project;
- make speculative inference an authoritative project fact;
- grant AI or extensions unrestricted write authority;
- require a distributed control plane before local operation proves
  insufficient; or
- standardize every software-development practice.

## Product strategy

Development follows four strategic moves:

1. Define stable product semantics and architectural boundaries.
2. Publish versioned, testable information and repository contracts.
3. Prove value through read-only project intelligence before adding mutation.
4. Add governed workflows, runtime capabilities, and extensions only after the
   earlier contracts are verified.

The implementation must remain local-first and simple until measured use cases
justify additional infrastructure.

## Qualitative success criteria

AOS is succeeding when:

- a new contributor or tool can discover the same current project truth;
- project knowledge remains useful after a chat, model, or provider changes;
- every authoritative fact can be traced to evidence and ownership;
- every proposed write can be explained, authorized, verified, and audited;
- extensions add capability without redefining core semantics; and
- a managed project can evolve its AOS data through explicit compatibility and
  migration rules.

Quantitative adoption or performance targets will be added only after executable
capabilities exist and can be measured.

## Relationship to other canonical documents

[PRINCIPLES.md](PRINCIPLES.md) constrains how this vision may be pursued.
[DESIGN.md](DESIGN.md) defines the reference model that realizes it.
[ROADMAP.md](ROADMAP.md) orders delivery without redefining product scope.
