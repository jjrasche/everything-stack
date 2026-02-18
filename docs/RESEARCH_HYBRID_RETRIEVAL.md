# Research Prompt: Hybrid Semantic + Graph Retrieval for LLM Memory

## Goal

Find research, papers, and production systems that combine these three retrieval strategies for LLM memory/context:

1. **Hierarchical semantic search** (domain/category tags narrowing vector search space)
2. **Graph traversal** (entity relations, multi-hop reasoning)
3. **Combined scoring** (merging semantic similarity with graph distance into one ranking)

## Specific Questions

### Hierarchical Semantic Search
- How do systems partition embedding space into navigable tiers (domain -> category -> item)?
- What clustering algorithms produce stable, meaningful hierarchies from flat embeddings?
- How does H-MEM's 4-level hierarchy achieve +14.98 F1 over flat search?
- Are there production systems using emergent (bottom-up) vs rigid (top-down) hierarchy?
- What is the optimal number of domain/category clusters for a personal knowledge base?

### Graph-Augmented Retrieval
- How does Zep/Graphiti combine bi-temporal graph with vector search (71.2% vs 60.2%)?
- What graph traversal strategies work best for multi-hop retrieval in knowledge graphs?
- How do systems decide traversal depth (1-hop vs 2-hop vs 3-hop)?
- What is the performance cost of graph traversal vs pure vector search at scale?
- How do GraphRAG, RAPTOR, and similar systems structure their graph layers?

### Combining Scores
- What scoring functions merge cosine similarity (semantic) with graph distance (structural)?
- Is there research on learned combination weights vs fixed formulas?
- How does re-ranking work when candidates come from two different retrieval paths?
- What are the precision/recall tradeoffs of semantic-first-then-graph vs graph-first-then-semantic?

### Entity Resolution Without LLMs
- Statistical/embedding-based entity resolution techniques (no LLM calls)
- Human-in-the-loop entity disambiguation with active learning
- Threshold tuning for auto-merge vs surface-to-user decisions
- How do systems handle entity evolution (name changes, merged concepts)?

### Production Systems
- Mem0, Zep, Graphiti, LangGraph memory, LlamaIndex knowledge graphs
- Any system combining all three strategies (hierarchy + graph + semantic)
- Benchmarks: LongMemEval, MemBench, or similar for measuring retrieval quality
- Cost/latency profiles of hybrid approaches vs pure vector search

## Context

This is for a personal AI system (Everything Stack) that:
- Extracts atomic insights from episodic input (conversations, articles, any text)
- Stores insights with embeddings in a vector index (HNSW, 8-12ms queries)
- Has an existing Edge entity supporting typed relations and 1-3 hop traversal
- Plans emergent hierarchy via consolidation (L0 session -> L1 week -> L2 project/life)
- Targets entity resolution without LLM calls (statistical + human-in-the-loop)
- Runs on-device across 6 platforms (cost and latency matter)

## Known Starting Points

| System | Key Contribution | Score |
|--------|-----------------|-------|
| H-MEM | 4-level hierarchy, +14.98 F1 over flat | Multi-hop +21.25 |
| Zep/Graphiti | Bi-temporal graph + vector hybrid | 71.2% vs 60.2% |
| SimpleMem | Affinity-based consolidation, 0.85 threshold | +26.4% F1 |
| A-MEM | Zettelkasten 7-field notes with links | NeurIPS 2025 |
| RAPTOR | Recursive tree summarization for retrieval | Hierarchical chunks |
| GraphRAG | Microsoft, graph communities + summarization | Multi-hop reasoning |
| Mastra OM | Append-only observations, prompt caching | 94.87% LongMemEval |

## Output Expected

- Papers with concrete architectures (not just "we used a graph")
- Benchmark comparisons showing hybrid vs single-strategy results
- Implementation details: data structures, scoring functions, traversal algorithms
- Failure modes: when does hybrid retrieval hurt rather than help?
- Cost analysis: token/compute overhead of hybrid vs pure semantic
