# Narrative Services Specification: Technical Audit

Status: Architecture Phase - Not shipped. Code exists but incomplete/untested.

## Executive Summary

What is built:
- NarrativeThinker: Extracts narratives on every turn (automatic)
- NarrativeRepository: Persistence + semantic search API
- NarrativeRetriever: Top-K retrieval with cosine similarity
- NarrativeCheckpoint: Consolidation logic exists (manual trigger)
- NarrativeEntry: Persistent domain entity with embedding field

What is missing:
- Checkpoint UI (stubbed - code says 'In real implementation, displays UI')
- Checkpoint time-based triggers (currently manual only)
- Semantic search testing (logic correct but untested)
- Extraction decision logic (always extracts, no conditional)
- Response queueing (mentioned but no code)
- IntentEngine narrative awareness (no narrative_decision field)

Bottom line: 60% infrastructure + 40% stubs.

## Question 1: What Data Flows Into Narratives?

NarrativeThinker.updateFromTurn() receives:
- utterance (string)
- intentOutput (map with classification, confidence, reasoning)
- chatHistory (list of messages, last 10 used)
- previousNarratives (list for deduplication)

Processing pipeline:
1. Build context (utterance + intent + history)
2. Call LLMService.chat() - single call returns candidates as JSON
3. Parse JSON array from response
4. Auto-save Session/Day entries

Issue: Extraction runs on EVERY turn. No conditional logic.
Each entry gets embedding via EmbeddingService.generate() - 384 floats.

## Question 2: Checkpoint Trigger Mechanism

Current: MANUAL ONLY - narrativeCheckpoint.train() called explicitly

Not implemented:
- Time boundaries (midnight, end of week)
- Event boundaries (app close)
- Query-time consolidation (before Intent classification)

Training flow:
Phase 1: Review and Filter (STUBBED UI)
- Get Session/Day narratives
- Show as cards, let user remove
- Mark for archival

Phase 2: Refine Projects/Life
- Build context from kept Session/Day
- Call Groq for suggestions
- Save new Project/Life entries

Returns: NarrativeDelta { added, removed, promoted }

## Question 3: Retrieval Strategy

API: findRelevant(query, topK=5, threshold=0.65)

Process:
1. Embed query (384 floats)
2. Compute cosine similarity vs all narratives
3. Filter: similarity >= 0.65
4. Sort: highest first
5. Limit: max 5 results
6. Exclude archived

Tested: JSON parsing, deduplication logic
Not tested: Real embeddings, threshold appropriateness, cross-scope search

## Question 4: Success Metrics

Extraction Quality (NOT MEASURED):
- Deduplication accuracy: target 0, no test
- Extraction recall: target >80%, no audit
- Extraction precision: target >70%, no audit

Retrieval Quality (NOT MEASURED):
- Relevance ranking (nDCG@5): target >0.7, no test
- Threshold appropriateness: target 3-5 results, no validation

Missing infrastructure for: token usage, latency, API calls, costs, satisfaction

## Question 5: Privacy and Retention

Built: Soft-delete via archive() and purgeArchivedBefore()
Storage: Local only (ObjectBox/IndexedDB). Optional Supabase sync.

Missing:
- No retention schedule (methods exist but never called)
- No export feature
- No delete-all feature
- No data residency controls

User control (when UI built): Review, remove, confirm, edit
Current: UI stubbed, no control exists

## Question 6: Visibility and Interface

Status: COMPLETELY STUBBED
Code comment: 'In real implementation, this displays a UI card with entries'

Missing:
- Narrative review dashboard
- Checkpoint trigger UI
- Project/Life confirmation
- Narrative context display

Current visibility:
Developers: Can inspect via findByScope(), getScopeSummary(), manual train()
End users: No UI, no control, no confirmation

## Implementation Roadmap

Phase 1: Extraction (3-5 days)
- Decision logic for when to extract
- Test with real embeddings
- Manual accuracy audit
- Token cost tracking

Phase 2: Checkpoint Infrastructure (2-3 days)
- Time-based scheduler
- Event logging
- Test without UI

Phase 3: User UI (5-7 days)
- Card-based review
- Removal interaction
- Integration

Phase 4: Privacy and Retention (2-3 days)
- Retention scheduler
- GDPR features

Phase 5: Observability (3-5 days)
- Metrics instrumentation
- A/B testing

## Next Steps for PM

1. Decide extraction granularity: every turn or only significant?
2. Prioritize checkpoint triggers: time/event/query-time?
3. Define retention policy: Session duration? Project/Life forever?
4. Plan UI mockups: cards? list? conversational?
5. Schedule metrics audit before shipping any UI

Last updated: Architecture phase 5 (technical audit complete)
