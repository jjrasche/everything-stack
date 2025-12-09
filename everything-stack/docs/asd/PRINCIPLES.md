# ASD Principles

Autonomous Software Development is a paradigm for building software with AI. AI implements, humans govern.

## Core Principles

### 1. Anchored

Every implementation decision traces back to foundation documents. Vision (why) defines purpose and success criteria. Architecture (what) defines technical boundaries and patterns. Roadmap (how) defines sequence and priorities.

AI consults foundation before implementing. Drift is caught by misalignment with these documents, not code review.

### 2. Contract-First

BDD scenarios define behavior before code exists. The scenario IS the requirement. Tests implement scenarios. Code satisfies tests.

Human writes scenario (what should happen). AI writes test (how to verify). AI writes code (how to make it happen). Human validates behavior matches intent.

### 3. AI-Built

AI writes all implementation code. Human never writes production code. Human role is governance: defining intent, approving contracts, validating outcomes.

This isn't about speed. It's about separation of concerns. Human expertise is knowing what to build. AI expertise is knowing how to build it.

### 4. Universal

Write once, run everywhere. Single codebase for all platforms. Single test suite validates all platforms. Platform-specific code isolated to thin adaptation layers.

This reduces surface area AI must understand. One implementation to reason about, not five.

## Anti-Patterns

**Human editing AI code:** If you're fixing implementation details, the contract was wrong. Fix the scenario, let AI re-implement.

**Skipping foundation:** Building features without Vision/Architecture leads to drift. Every feature should trace to foundation.

**Testing after implementation:** Contract-first means tests exist before code. Testing after is verification theater.

**Platform-specific shortcuts:** "Just for iOS" becomes technical debt. Universal or don't build it.
