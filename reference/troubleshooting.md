# Exa Troubleshooting & Configuration

## Error Handling

| Error | Cause | Action |
|-------|-------|--------|
| No results | Query too specific or no matching content | Broaden query, try without category filter |
| 429 Too Many Requests | Rate limit exceeded | Script auto-retries with next API key; fails only after all keys exhausted |
| 401 Unauthorized | Invalid or missing API key | Check EXA_API_KEY is set correctly |
| 400 Bad Request | Invalid parameters | Check query format and category spelling |
| 5xx Server Error | Exa service issue | Retry after brief wait |

## Environment Configuration

```bash
# Single API key
export EXA_API_KEY="your-key-here"

# Multiple API keys (comma-separated) - rotated with automatic 429 failover
export EXA_API_KEY="key1,key2,key3"

# Get a key at: https://dashboard.exa.ai/api-keys
```

## Rate Limits

| Endpoint | Limit |
|----------|-------|
| `/search` | 5 QPS |
| `/contents` | 50 QPS |
| `/answer` | 5 QPS |
| `/findSimilar` | 5 QPS |

*QPS = Queries Per Second*

## Common Issues

### Query Specificity

Poor queries return irrelevant results. Be specific:

| Bad Query | Good Query |
|-----------|------------|
| "AI" | "latest LLM research papers on context windows 2024" |
| "React" | "React 19 Server Components migration guide" |
| "startup funding" | "AI startup funding rounds Q4 2024" |

### Category Selection

Use categories to narrow results:

| Category | Best For |
|----------|----------|
| `research paper` | Academic papers, arXiv, scientific content |
| `news` | Current events, announcements |
| `github` | Code repositories, open source projects |
| `company` | Company websites, about pages |
| `people` | LinkedIn profiles, personal sites |
| `pdf` | PDF documents, whitepapers |

### Code Search Tips

For programming queries, the `code` command searches developer-focused domains:
- github.com
- stackoverflow.com
- dev.to
- medium.com (tech articles)
- npmjs.com / pypi.org

```bash
# Good code queries
scripts/exa.sh code "React useCallback TypeScript generic types"
scripts/exa.sh code "Python async await best practices FastAPI"
scripts/exa.sh code "Rust lifetime annotations examples"
```
