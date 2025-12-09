# Architecture Template

Work through these questions after Vision is solid. This defines WHAT gets built technically.

---

## Patterns Selection

Review `lib/patterns/`. For each, decide: needed for this project?

| Pattern | Include? | Rationale |
|---------|----------|-----------|
| Embeddable | ? | Semantic search needed? |
| Temporal | ? | Due dates, scheduling, recurrence? |
| Ownable | ? | Multi-user isolation? |
| Versionable | ? | Change history, conflict resolution? |
| Locatable | ? | Geographic features? |
| Edgeable | ? | Flexible entity relationships? |

**Prompts:**
- Which patterns are obviously needed?
- Which might be needed later? (leave out for now, add when needed)
- Which are definitely not relevant?

---

## Domain Entities

What are the core things in this domain?

*List entities, brief description, which patterns each needs.*

**Example:**
```
Tool
  - What it is: A borrowable item
  - Patterns: Embeddable (search), Ownable (who owns it), Locatable (where is it)
  
BorrowRequest
  - What it is: A request to borrow a tool
  - Patterns: Temporal (when needed), Ownable (who requested)
```

**Prompts:**
- What nouns appear in the Vision?
- What do users create, view, modify?
- What relationships exist between entities?

---

## Platform Targets

Which platforms for v1?

- [ ] iOS
- [ ] Android
- [ ] Web
- [ ] macOS
- [ ] Windows
- [ ] Linux
- [ ] Embedded/IoT

**Prompts:**
- Where will the first user use this?
- What's the minimum viable platform set?
- Which platforms can wait for v2?

---

## Data & Sync

How does data flow?

**Offline behavior:**
- What works offline?
- What requires connection?

**Sync requirements:**
- Single user, single device? (Isar only, no Supabase)
- Single user, multi device? (Isar + Supabase backup)
- Multi user? (Isar + Supabase with ownership)

**Prompts:**
- Will users have internet reliably?
- Do users need to share data?
- What's the conflict resolution strategy?

---

## External Integrations

What outside systems does this connect to?

*APIs, services, hardware, etc.*

**Prompts:**
- What data comes from outside?
- What data goes outside?
- What happens when integrations fail?

---

## Scale Expectations

How big does this get?

- Users: ? (10? 1,000? 100,000?)
- Data per user: ? (KB? MB? GB?)
- Geographic distribution: ? (local? regional? global?)

**Prompts:**
- What's realistic for year one?
- What would success-case growth look like?
- What scale would break current architecture?

---

## Security & Privacy

What needs protection?

**Prompts:**
- What data is sensitive?
- Who can see what?
- What compliance requirements exist?

---

# After Discovery

Crystallize into `ARCHITECTURE.md`:

- Selected patterns (table with rationale)
- Entity definitions (name, description, patterns, key fields)
- Platform targets for v1
- Data/sync approach
- Integration points
- Scale assumptions
- Security notes

Delete this template file. ARCHITECTURE.md is the living document.
