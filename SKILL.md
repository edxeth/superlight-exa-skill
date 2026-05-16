---
name: exa
description: Searches the web using Exa's neural embeddings-based search API. Use when needing real-time web information to answer questions, verify facts, debug issues, find code examples, research topics, or clear doubts with authoritative sources. Best for open-ended research, fact-checking, troubleshooting errors with web context, and getting AI answers with citations.
---

# Exa Web Search

AI-powered semantic web search for real-time information, research, and fact verification. Returns full page text, highlights, and published dates.

## When to Use

| Situation | Use Exa | Don't use Exa |
|---|---|---|
| Find sources on a topic | `search` with highlights | — |
| Get full page content | `contents` with URL | Use TinyFish `fetch` (returns more content) |
| Find similar pages | `similar` on a known URL | — |
| Quick factual answer | `answer` with question | — |
| Code/library examples | `code` with query | — |
| Scrape JS-heavy sites | — | Use TinyFish or Firecrawl |
| Crawl entire sites | — | Use Firecrawl `crawl` or `map` |

**Exa is for discovery. TinyFish is for fetching. Firecrawl is for crawling.**

## Protocol

### Search

```bash
scripts/exa.sh search "<query>" [numResults] [category] [--start-date ISO] [--end-date ISO] [--type TYPE] [--domains LIST] [--exclude-domains LIST] [--json]
```

**Categories**: `company`, `research paper`, `news`, `personal site`, `financial report`, `people`

**Search types**: `auto` (default), `neural`, `keyword`, `deep`, `deep-reasoning`, `instant`

**Examples:**
```bash
scripts/exa.sh search "latest LLM research" 5 "research paper"
scripts/exa.sh search "AI agent memory 2026" 10 --start-date 2025-01-01T00:00:00.000Z
scripts/exa.sh search "React server components" 5 --domains "react.dev,nextjs.org"
scripts/exa.sh search "deep research" 5 --type deep-reasoning --json
```

### Get Page Contents

```bash
scripts/exa.sh contents "<url1>" ["<url2>" ...] [--highlights] [--summary] [--max-chars N] [--subpages N] [--json]
```

**Options:**
- `--highlights` — Return key excerpts (10x more token-efficient than full text)
- `--summary` — Return LLM-generated summary
- `--max-chars N` — Limit characters per page (server-side)
- `--subpages N` — Crawl N subpages per URL
- `--json` — Output raw JSON

**Examples:**
```bash
scripts/exa.sh contents "https://arxiv.org/abs/2307.06435" --highlights
scripts/exa.sh contents "https://docs.anthropic.com" --subpages 5 --max-chars 5000
```

### Find Similar Pages

```bash
scripts/exa.sh similar "<url>" [numResults]
```

Returns similar pages with full text, highlights, and published dates.

### Get AI Answer with Citations

```bash
scripts/exa.sh answer "<question>"
```

### Search Code Context

```bash
scripts/exa.sh code "<programming query>"
```

Searches GitHub, Stack Overflow, dev.to, npm, PyPI with code-focused results.

## Output

All commands return full text content (no truncation), highlights, and published dates by default. Use `--json` for raw structured output.

## Critical Rules

1. **Specific queries win** — "React useState TypeScript patterns" beats "react hooks"
2. **Use date filters for recency** — Add `--start-date` for "latest/current/2026" queries
3. **Use highlights for efficiency** — `contents --highlights` is 10x more token-efficient
4. **Valid categories only** — company, research paper, news, personal site, financial report, people
5. **No guessing** — If search returns nothing, rephrase once then ask user

## Resources

See `reference/troubleshooting.md` for error handling, configuration, and common issues.
