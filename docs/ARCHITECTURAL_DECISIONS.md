# Architectural Decisions

This document records significant architectural decisions made for the Everything Stack template.

## AD-001: Database-Agnostic Domain Entities

**Date:** 2025-12-12

**Status:** Accepted

**Decision:** Domain entities use only `@JsonSerializable` annotations. No database-specific annotations (ObjectBox, etc.).

**Context:**
- Everything Stack targets all platforms equally: Android, iOS, macOS, Windows, Linux, Web
- Web compilation requires entities without `dart:ffi` dependencies
- ObjectBox annotations (`@Entity`, `@Id`, `@Unique`, `@Index`, `@HnswIndex`) transitively import `dart:ffi`
- Dart web compiler fails when any reachable code imports `dart:ffi`, even through conditional imports

**Rationale:**
1. **Web support is mandatory** - Not optional, not "nice to have"
2. **Platform abstraction belongs in adapters** - Domain entities should be persistence-agnostic
3. **AI-augmented development reduces need for compile-time safety** - Tests catch query errors
4. **ObjectBox can work programmatically** - Annotations are syntactic sugar, not required

**Trade-offs Accepted:**

✅ **Gains:**
- Web compilation works
- True platform abstraction
- Domain entities remain pure business logic
- Same entity classes work with ObjectBox and IndexedDB

❌ **Costs:**
- ObjectBox loses generated query conditions (e.g., `Note_.uuid.equals(uuid)`)
- Must use programmatic queries in ObjectBox adapters
- Slightly more verbose adapter code
- No compile-time query validation

**Implementation:**
- Remove all ObjectBox annotations from `Note`, `Edge`, `EntityVersion`
- Keep `@JsonSerializable()` for JSON serialization
- ObjectBox adapters use programmatic query API
- Platform-specific `BaseEntity` handles `@Id()` annotation differences

**Alternatives Considered:**

1. **Platform-specific entity classes** - Rejected: Defeats purpose of universal domain model
2. **Code generation for platform variants** - Rejected: Too complex, hard to maintain
3. **Abandon web support** - Rejected: Violates "ALL platforms first-class" principle
4. **Use different database on web** - Accepted: IndexedDB for web, ObjectBox for native

**Consequences:**
- Adapter layer becomes slightly more complex
- Domain layer becomes simpler and more portable
- Web platform fully supported
- 366-test suite validates both persistence backends
