# Narrative Architecture - Production Readiness Checklist

## Overview

Battle-tested requirements for Narrative to be production-ready. Each item must be verified and passing before deployment.

---

## ✅ Core Functionality Verification

### Persistence Layer
- [ ] NarrativeEntry persists correctly to ObjectBox
- [ ] Fields are properly stored: `content`, `scope`, `type`, `projectId`, `isArchived`, `archivedAt`
- [ ] Embedding vectors stored as `Float64List` in ObjectBox
- [ ] Sync fields (`syncId`, `syncStatus`) properly handled
- [ ] All timestamps (`createdAt`, `updatedAt`) auto-populated

**Test**: `test/integration/narrative_full_stack_test.dart` → "Session narratives persist to ObjectBox"

### Semantic Search
- [ ] Embeddings generated via EmbeddingService (not hardcoded to any provider)
- [ ] Cosine similarity calculation is correct (matches reference implementation)
- [ ] Top-K filtering works (returns at most K results)
- [ ] Threshold filtering works (filters below 0.65 similarity)
- [ ] Archived entries excluded from search results
- [ ] Empty embedding vectors handled gracefully (no crashes)

**Test**: `test/integration/narrative_full_stack_test.dart` → "Semantic search returns relevant entries"

### Scope Independence
- [ ] Session scope: auto-created on app launch, resets on app close
- [ ] Day scope: auto-created on first entry after midnight (not manually)
- [ ] Week scope: auto-created on first entry after Monday 00:00
- [ ] Project scope: user-created only (never auto-created)
- [ ] Life scope: singleton, never resets, created on first app launch
- [ ] No auto-bubbling: Session entries don't appear in Day queries
- [ ] Scopes are queryable independently

**Test**: `test/integration/narrative_full_stack_test.dart` → "Scope independence: Day does not auto-populate from Session"

### Archive Pattern
- [ ] Archive: Sets `isArchived = true` and `archivedAt = DateTime.now()`
- [ ] Unarchive: Sets `isArchived = false` and `archivedAt = null`
- [ ] Archived entries excluded from active queries (default behavior)
- [ ] Archived entries retrievable with `includeArchived: true`
- [ ] Soft delete: Entry remains in database, not physically removed
- [ ] Purge old archives: Can delete entries archived > N days

**Test**: `test/integration/narrative_full_stack_test.dart` → "Archive pattern: entries soft-deleted but retained"

---

## ✅ NarrativeThinker (Extraction) Quality

### Prompt Correctness
- [ ] Prompt includes dedup instruction: "Skip if redundant with existing narratives"
- [ ] Prompt enforces format: "[Atomic idea]. Because [reason]."
- [ ] Prompt restricts length: "One sentence per entry"
- [ ] Prompt defines scopes correctly: session/day/week/project/life with clear rules
- [ ] Prompt forbids inventing projects/life: "Only surface what's evident"
- [ ] Prompt returns JSON ONLY: "Return empty array [] if nothing new"

**Test**: Review prompt in `lib/services/narrative_thinker.dart` at `_systemPrompt()` method

### Deduplication
- [ ] Groq prompt includes redundancy check
- [ ] Identical/near-identical entries are skipped (90%+ semantic match)
- [ ] Dedup comparison includes all existing narratives (from all scopes)
- [ ] No false negatives: Similar entries are caught
- [ ] No false positives: Different ideas are distinguished

**Test**: `test/integration/narrative_full_stack_test.dart` → "Deduplication: identical entries detected and skipped"

### Entry Validation
- [ ] Content is non-empty
- [ ] Content includes "[Idea]. Because [reason]" pattern
- [ ] Scope is valid: one of session/day/week/project/life
- [ ] Type is valid: one of learning/project/exploration
- [ ] No hallucinated entries (Groq doesn't invent false insights)
- [ ] Prompt prevents multi-sentence entries (one atomic idea only)

**Test**: `test/prompts/narrative_thinker_prompt_test.dart` (to be created) - runs test cases against actual Groq API

### Session/Day Auto-Update
- [ ] Session entries saved immediately after Groq extraction
- [ ] Day entries saved immediately after Groq extraction
- [ ] Project entries NOT auto-saved (remain provisional until training)
- [ ] Life entries NOT auto-saved (remain provisional until training)
- [ ] Updates happen on turn boundary (utterance processing completes)
- [ ] No provisional/temp tables: saves go directly to active storage

**Test**: `test/services/narrative_thinker_test.dart` (unit test)

---

## ✅ NarrativeRetriever (Search) Quality

### Semantic Relevance
- [ ] Top-5 results are genuinely relevant to query (not random noise)
- [ ] Similarity scores are meaningful (cosine similarity 0-1 scale)
- [ ] Threshold filtering removes irrelevant matches
- [ ] Order is correct: highest similarity first
- [ ] No "near misses": entries below threshold are truly irrelevant

**Test**: `test/integration/narrative_full_stack_test.dart` → "Semantic search returns relevant entries"

### Context Formatting
- [ ] Formatted output is LLM-ready (no special characters, clean text)
- [ ] All entries shown: no truncation
- [ ] Metadata visible: scope and type tags shown
- [ ] Order preserved: highest relevance first in formatted output

**Test**: `test/integration/narrative_full_stack_test.dart` → "NarrativeRetriever formats entries for Intent Engine context"

### Scope Filtering
- [ ] Session always included (current context)
- [ ] Day included if relevant (by threshold)
- [ ] Week included if relevant (by threshold)
- [ ] Project included if relevant AND matches projectId filter
- [ ] Life included if relevant (identity patterns)
- [ ] Custom scope lists work: can restrict to specific scopes

**Test**: Unit test for scope parameter

---

## ✅ NarrativeCheckpoint (Training) Quality

### Training Flow
- [ ] Triggered by: time boundary (midnight, end of week) OR explicit user command
- [ ] Shows Session narratives as cards (user can remove)
- [ ] Shows Day narratives as cards (user can remove)
- [ ] Drives conversational refinement for Projects/Life (via Groq)
- [ ] Records deltas: added, removed, promoted entries
- [ ] User edits persisted to database

**Test**: `test/integration/narrative_full_stack_test.dart` → "Training checkpoint collects and records deltas"

### Project/Life Suggestion (AI-Driven)
- [ ] Groq suggests projects from session narratives
- [ ] Groq suggests life themes from multi-day patterns
- [ ] Suggestions are conservative (not over-generalized)
- [ ] Suggestions are atomic: "[Idea]. Because [reason]."
- [ ] User can edit/refine suggestions via chat (not just picking from list)
- [ ] Only confirmed suggestions saved to database

**Test**: `test/prompts/narrative_checkpoint_prompt_test.dart` (to be created)

### Delta Recording
- [ ] Delta captures: what was added, removed, promoted
- [ ] Delta is passed to Trainer service
- [ ] Trainer learns from user edits (corrections → training signals)
- [ ] Deltas are logged for analysis

**Test**: Unit test for delta structure

---

## ✅ Prompt Testing (3Cs Framework)

### Thinker Prompt Tests

| Test Case | Status | Notes |
|-----------|--------|-------|
| `extract-clear-learning` | [ ] | Should extract [idea]. Because [reason]. in session scope |
| `dedup-redundant-entry` | [ ] | Should return [] (skip redundant) |
| `extract-project-explicit` | [ ] | Should extract with scope=session (not project) on first mention |
| `no-false-positives` | [ ] | Should return [] for casual statements |
| `format-validation` | [ ] | Response must be valid JSON, nothing else |

**How to run**:
```bash
flutter test test/prompts/narrative_thinker_prompt_test.dart \
  --dart-define=GROQ_API_KEY=your-key
```

### Checkpoint Prompt Tests

| Test Case | Status | Notes |
|-----------|--------|-------|
| `suggest-emerging-project` | [ ] | Should suggest project when 3+ related entries |
| `suggest-life-identity` | [ ] | Should suggest life identity on strong multi-day pattern |
| `skip-insufficient-evidence` | [ ] | Should return [] for single mention |
| `format-json-only` | [ ] | Response must be valid JSON array only |

**How to run**:
```bash
flutter test test/prompts/narrative_checkpoint_prompt_test.dart \
  --dart-define=GROQ_API_KEY=your-key
```

### Rubric Alignment
- [ ] Rubrics match prompts exactly (no misalignment)
- [ ] When prompt updated, rubric updated too
- [ ] Rubric criteria are atomic and testable
- [ ] Test failures give actionable feedback (which criterion failed)

**How to verify**: Compare `lib/services/narrative_thinker.dart::_systemPrompt()` with `test/framework/narrative_rubric.dart::_checkClearLearningExtraction()` - they should align

---

## ✅ Integration Testing

### Full Stack Tests
- [ ] ObjectBox initialization works (no schema errors)
- [ ] Groq API calls complete (no auth/network failures)
- [ ] EmbeddingService works (embeddings generated)
- [ ] End-to-end flow: utterance → Thinker → save → Retriever → format → success

**Test**: `test/integration/narrative_full_stack_test.dart`

### Intent Engine Integration
- [ ] NarrativeRetriever successfully injects context into Intent Engine prompt
- [ ] Intent Engine uses narrative context (verified in log/output)
- [ ] Context doesn't break Intent Engine (format compatible)

**Test**: Integration test with Intent Engine (in separate test file)

### Trainer Integration
- [ ] NarrativeCheckpoint deltas passed to Trainer service
- [ ] Trainer records learning signals from narrative edits
- [ ] Deltas are structured correctly for Trainer to consume

**Test**: Integration test with Trainer service

---

## ✅ Edge Cases & Error Handling

### Embeddings Service Unavailable
- [ ] If EmbeddingService returns null: semantic search returns []
- [ ] No crashes, graceful degradation
- [ ] User can still use system (just without semantic search)

**Test**: Unit test with MockEmbeddingService returning null

### Groq API Failures
- [ ] If Groq call fails: Thinker returns [] (no entries extracted)
- [ ] Error logged but doesn't crash app
- [ ] Next turn can retry

**Test**: Unit test with failing Groq service

### Invalid JSON from Groq
- [ ] If Groq returns invalid JSON: parse failure caught
- [ ] Invalid entries skipped
- [ ] Valid entries in same response still saved

**Test**: Unit test with malformed Groq response

### Empty Database
- [ ] Queries on empty database return [] (not errors)
- [ ] First entry creation works
- [ ] Semantic search works with few entries (not just many)

**Test**: Unit test starting from blank state

### Large Datasets
- [ ] Semantic search on 1000+ entries is fast (< 100ms)
- [ ] Archive cleanup on 10000+ old entries completes
- [ ] No memory leaks or excessive allocations

**Test**: Performance test (not included, flagged for future)

---

## ✅ Cross-Platform Verification

### iOS/Android (ObjectBox Native)
- [ ] NarrativeEntry model generates via build_runner
- [ ] ObjectBox adapter works on real device
- [ ] Embeddings stored and retrieved correctly
- [ ] Archive pattern works

**How to verify**: Run on iOS simulator/Android emulator

### Web (IndexedDB Fallback)
- [ ] NarrativeEntry works with IndexedDB
- [ ] Semantic search works (embeddings still searchable)
- [ ] Archive pattern works
- [ ] No ObjectBox-specific code leaks into web build

**How to verify**: Build and test on web platform

### Desktop (ObjectBox Native)
- [ ] Same as iOS/Android (native ObjectBox)
- [ ] Test on macOS, Windows, Linux

**How to verify**: Run on desktop

---

## ✅ Production Deployment Checklist

### Configuration
- [ ] Bootstrap correctly initializes all 5 services (Thinker, Retriever, Checkpoint, Repo, …)
- [ ] EmbeddingService provider configured (Jina, Gemini, local ONNX)
- [ ] Groq API key available and authenticated
- [ ] ObjectBox schema migrations handled (if updating)

### Monitoring
- [ ] Error logs captured for Groq failures
- [ ] Performance metrics tracked: Groq latency, semantic search latency
- [ ] Dedup accuracy monitored (% of redundant entries caught)
- [ ] Training delta frequency tracked (how often users refine)

### Documentation
- [ ] Integration guide complete and tested
- [ ] Prompt testing guide documented
- [ ] Emergency runbook: "If semantic search breaks, how to fix"
- [ ] Troubleshooting guide for common failures

---

## ✅ Sign-Off Verification

### Code Review
- [ ] Code reviewed by at least one other engineer
- [ ] No hardcoded API keys or secrets
- [ ] No console.log/print statements (use logger)
- [ ] All TODOs are tracked in issues

### Testing Coverage
- [ ] Unit test coverage: > 80%
- [ ] Integration test coverage: all critical paths
- [ ] Prompt test coverage: all prompt test cases passing

### Performance
- [ ] Semantic search: < 100ms for 1000 entries
- [ ] Groq extraction: < 3 seconds per turn
- [ ] Training checkpoint: < 5 seconds
- [ ] Memory usage: < 50MB for typical usage

---

## ✅ Final Checklist

- [ ] All tests passing
- [ ] All integration tests passing with real APIs
- [ ] All prompt tests passing with Groq
- [ ] Cross-platform tests passing (iOS, Android, web, desktop)
- [ ] Production checklist completed
- [ ] Code review approved
- [ ] Documentation complete and accurate
- [ ] Ready for deployment ✈️

---

## Notes for PM

This checklist represents production-grade quality:
- **Prompt testing** with rubric validation (3Cs pattern)
- **Integration tests** with real services (not mocks)
- **Cross-platform verification** (all target platforms)
- **Edge case handling** (graceful degradation, error handling)
- **Performance verification** (speed requirements met)

All items must be verified and signed off before production deployment.
