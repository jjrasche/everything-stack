# Vision

## What is this?

**Universal infrastructure for autonomous software development.**

Everything Stack is a complete application template that solves ALL infrastructure problems once. Small language models build applications by writing ONLY domain logic - entities, business rules, and behavior specifications. They never make architectural decisions, choose databases, design sync protocols, or solve platform-specific problems.

Includes a working notes app that demonstrates all patterns: entities, mixins, repository, offline-first sync, auth, semantic search.

## Why does it exist?

**To make autonomous software development efficient and standardized.**

Small models are good at domain logic but bad at infrastructure decisions. Everything Stack removes those decisions entirely. The model doesn't choose between ObjectBox vs Drift vs Isar - that's decided. It doesn't design web persistence differently than native - that's abstracted. It just defines entities and writes business logic.

This enables:
- One model can build many different applications
- Applications are consistent and maintainable
- Infrastructure bugs are fixed once, not per-project
- New capabilities benefit all applications simultaneously

## What does success look like?

1. A small model receives a product requirement
2. It clones Everything Stack
3. It writes domain entities and BDD scenarios
4. It implements business logic until tests pass
5. Application works on ALL platforms without platform-specific thinking
6. Human reviews behavior, not implementation

## Who is it for?

**Primary:** Small language models doing autonomous software development.

**Secondary:** Human developers who want production-ready infrastructure without building it themselves.

**Not for:** Developers who want to understand every implementation detail. This is infrastructure - you use it, not learn it.

## What is it NOT?

- Not a framework to learn - it's infrastructure to use
- Not a boilerplate with empty folders - it's a working, complete system
- Not something that works "eventually" - the template itself must be deployable
- Not "native-first with web as optional" - ALL platforms are requirements
- Not simplified for easier understanding - complexity serves completeness
