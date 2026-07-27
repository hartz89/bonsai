# Design notes

Architectures considered and declined, with the reasoning. Separate from `docs/roadmap.md`'s "Deliberately
not planned" list, which records *what* was declined; this records *why*, at the length the argument needs.

A note here is a snapshot. Each carries a verification date, and the landscape claims inside one are
registered in `docs/claims.md` if they assert anything about what other tools do.

---

## Why not a vector database

*Verified 2026-07-26.*

The recurring question. bonsai accumulates observations across sessions and decides what becomes
configuration — which sounds exactly like the problem embedding-based memory systems solve. It isn't, and
the difference is worth stating precisely, because the honest version of this argument concedes more than
the dismissive version.

### Draw the line by layer, not by technology

The weak version of this note argues "flat files beat vector search," which nobody proposed and which
would be wrong at scale anyway. The real boundary is between two layers with opposite cost models:

| | Episodic corpus (observations, candidates) | Resident set (rules, skills, subagents) |
| :--- | :--- | :--- |
| Grows | Without bound, one entry per session | Bounded — ~350 tokens, enforced |
| Bottleneck | **Recall.** Storage is cheap; finding the relevant entry is hard | **Eviction.** Every entry taxes every session forever |
| Question asked | "Have I seen something like this before?" | "Should this exist at all?" |
| Retrieval step | Yes — query-time, over history | **None.** It's already in the context window |

Embeddings are a recall tool. They answer the first question well and have nothing to say about the second,
because there is no query to be similar *to*: the artifact is loaded on every turn regardless. Cosine
similarity cannot tell you whether a rule earns 40 permanent tokens.

So the answer isn't "no vectors." It's **vectors may earn a place in candidate recall; they can never be
what decides residency.** Invariant 6 already forces this — no score reaches always-on context without human
approval — which means a retrieval layer is structurally incapable of being the decision-maker here.

### Why not in the resident path specifically

1. **A similarity score isn't reviewable evidence.** The approval gate needs an argument a human can check.
   "This rule has not loaded in 60 days" is a fact from `.state/exercised`. "0.83 cosine to an existing
   rule" is a number whose meaning depends on an embedding model version — and re-embedding under a new
   version silently changes past decisions with no audit trail. That is the determinism boundary
   (`reference/determinism.md`) failing in the direction that matters.
2. **It doesn't fit on the hot path.** An embedding call means a model round-trip or a local model load at
   `SessionStart`. Invariant 4 says bonsai can never make the user wait; invariant 5 keeps `pending.sh` and
   `retro.sh` pure POSIX `sh` precisely so a missing interpreter can't break a session. A vector store adds
   an index, a dependency, and a failure mode to the one path that must not have any.
3. **Vector stores are built to remember, not to forget.** Not being a nearest neighbour doesn't mean an
   entry is dead — only that something scored higher this round. You still need an independent staleness
   signal, which is the load record bonsai already has. The vector layer would sit *on top of* the actual
   evidence without replacing it.
4. **The numbers don't reach the threshold.** Anthropic's own tool-search guidance suggests embeddings once
   you pass **~20 specialized tools** and calls **>100 impractical** to inline
   ([cookbook](https://platform.claude.com/cookbook/tool-use-tool-search-with-embeddings)). bonsai's
   resident inventory is dozens of artifacts at the high end. Exact match on a path or a name beats
   approximate nearest neighbour at that size, on accuracy as well as cost.

### The field already moved this way

Worth knowing if anyone frames vector memory as the mature option — the mature implementations converged on
structure, currency, and usage signals rather than similarity alone:

- **Letta / MemGPT** keeps a small always-resident tier — *memory blocks*, historically *core memory* —
  pinned to the context window, agent-editable, with hard limits (~2,000 chars per block, guidance of
  <20 blocks and <50k chars total), entirely separate from its semantically-searched *archival memory*
  ([docs](https://docs.letta.com/guides/core-concepts/memory/context-hierarchy/)). The flagship
  agent-memory system does not embed its always-loaded instructions. It budgets them. bonsai's ceiling is
  the same shape two orders of magnitude smaller.
- **Zep / Graphiti** uses a bi-temporal knowledge graph where facts carry validity windows and are
  *invalidated rather than deleted*, with retrieval fusing embeddings, BM25, and graph traversal
  ([repo](https://github.com/getzep/graphiti), [arXiv 2501.13956](https://arxiv.org/abs/2501.13956)). Its
  "Stop Using RAG for Agent Memory" writeup names the failure modes directly — temporal blindness, missing
  causality, no fact invalidation ([blog](https://blog.getzep.com/stop-using-rag-for-agent-memory/)).
- **Mem0** extracts facts with an LLM rather than embedding raw turns, and fuses semantic, BM25, and
  entity-match signals at retrieval ([repo](https://github.com/mem0ai/mem0)). Notably its 2026 v3 rewrite
  moved *away* from explicit ADD/UPDATE/DELETE to single-pass ADD-only accumulation
  ([migration](https://docs.mem0.ai/migration/oss-v2-to-v3)) — currency resolution pushed into ranking
  instead of into writes.
- **LangMem** manages *procedural* memory — instructions that shape behavior, the closest analogue to a
  `CLAUDE.md` rule — by explicit consolidation and rewrite, not by embedding retrieval
  ([launch post](https://www.langchain.com/blog/langmem-sdk-launch)).

All of these use embeddings as *one signal*. None of them uses pure cosine retrieval, and none embeds its
always-resident tier. The durable trend is explicit **currency management** — validity windows,
invalidation, consolidation, recency-weighted ranking — not explicit deletion. Deletion stays rare in
episodic memory systems, which is itself the point: removal is native to config curation and awkward for a
memory store. That's an architectural difference, not a shared trend.

### The harness is the strongest precedent

Claude Code already made both of these calls, in bonsai's favour, in its own design:

- **Skill selection is description-based progressive disclosure, with no embedding step.** Metadata sits in
  the system prompt; the model reads descriptions and decides what to load
  ([skills](https://code.claude.com/docs/en/skills)).
- **When the skill listing overflows its budget, Claude Code evicts by usage frequency** — dropping
  descriptions "starting with the skills you invoke least." A usage signal applied to config curation,
  shipped in the harness, with no vectors involved. That is precedent for exactly what `/bonsai:prune` does.
- **`CLAUDE.md` is loaded in full at launch, every session**, with no retrieval step; `@path` imports
  "help organization but don't reduce context" ([memory](https://code.claude.com/docs/en/memory)). The only
  conditional loading is glob-based (`paths:` frontmatter) — path matching, not similarity.
- **Claude Code shipped a local vector index early and removed it in May 2025** in favour of agentic
  grep/glob search, on the grounds that it performed better without an index's staleness, security, and
  privacy costs. Same vendor, same product, same trade-off.

### What would genuinely earn embeddings

Conceded, in descending order of strength — all of these live *behind* the approval gate, in candidate
recall, never in the resident path:

1. **Retrieval over the observation log.** "Have I seen this correction before, across 200 sessions?" This
   is the legitimate shape, and the corpus really does grow without bound.
2. **Semantic clustering to surface redundancy an author can't see** — "these six rules across four files
   are all about error handling." The payoff is a *merge* proposal, which reduces resident tokens. Squarely
   in the value proposition.
3. **Conflict detection.** Contradictory rules are often lexically dissimilar, and the harness warns that
   "if two rules contradict each other, Claude may pick one arbitrarily." Embeddings do recall; the model
   adjudicates. That respects the determinism boundary rather than violating it.
4. **Trigger-collision analysis.** Two skill descriptions that embed close together will get confused. A
   cheap pre-filter ahead of behavioral evaluation.
5. **Near-duplicate detection at proposal time** — the narrowest case, and the one where an LLM read of a
   30-item inventory is probably cheaper and more explainable anyway.

None of this is built, and none of it is scheduled. It's recorded so the next person who asks gets the
boundary rather than a reflex.

### The strongest objection to this note

That it wins a narrow argument while ducking a wider one. Nobody credible would put 350 tokens of resident
rules behind a vector index — so proving that unwise proves little. The live question is what happens on the
other side of the boundary: the candidate pool and the observation log both grow without bound even though
the resident output doesn't, and Anthropic's own ~20-artifact threshold is inside the range bonsai will
reach. If similarity search ever earns a place here, it earns it in the proposal pipeline, and the answer to
"why not a vector database" becomes "not yet, and never in the resident path."

One caution against over-reading the gap: no OSS tool appears to do embedding-based config or rule dedup
today, but absence of a tool is weak evidence of a bad idea. The accurate statement is "we know of none,"
not "it doesn't work."
