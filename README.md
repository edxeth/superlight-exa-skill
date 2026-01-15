# Superlight Exa Skill

AI-powered semantic web search via the Exa API. A superlight agent skill for AI coding assistants — minimal tokens, maximum discovery. Supports multiple API keys with round-robin rotation and automatic 429 failover.

## Features

- **Semantic web search** — AI-powered embeddings-based search for relevant content
- **Fact verification** — Clear doubts and verify information with authoritative sources
- **Debugging support** — Search for error solutions, stack traces, and troubleshooting guides
- **AI answers** — Get LLM-generated answers with citations
- **Code search** — Developer-focused search across GitHub, StackOverflow, etc.
- **Similar pages** — Find pages similar to a reference URL
- **Token-efficient** — Minimal context overhead with progressive disclosure
- **Multi-key rotation** — Round-robin distribution with automatic 429 failover

## Token Budget

Uses Claude's [progressive disclosure](https://docs.anthropic.com/en/docs/agents-and-tools/agent-skills) architecture:

| Level | When Loaded | Content | Tokens |
|-------|-------------|---------|--------|
| **Metadata** | Always (startup) | Skill description | ~80 |
| **Instructions** | When triggered | SKILL.md protocol | ~400 |
| **Resources** | As needed | troubleshooting.md | ~400 |

## Installation

### Claude Code

```bash
git clone https://github.com/edxeth/superlight-exa-skill.git ~/.claude/skills/exa
```

### Manual Installation

```
~/.claude/skills/exa/
├── SKILL.md
├── reference/
│   └── troubleshooting.md
└── scripts/
    └── exa.sh
```

## Usage

The skill triggers automatically when searching for web content:

```
"Find the latest research on LLM context windows"
"What is SpaceX's current valuation?"
"Find similar pages to this GitHub repo"
"Search for React useCallback TypeScript examples"
```

### Manual Invocation

```bash
# Web search
./scripts/exa.sh search "latest AI research" 5 "research paper"

# Get page contents
./scripts/exa.sh contents "https://arxiv.org/abs/2307.06435"

# Find similar pages
./scripts/exa.sh similar "https://github.com/anthropics/anthropic-cookbook" 5

# AI answer with citations
./scripts/exa.sh answer "What is the current valuation of SpaceX?"

# Code-focused search
./scripts/exa.sh code "React useCallback hook TypeScript examples"
```

## API Endpoints

Uses Exa REST API:

| Endpoint | Purpose | Rate Limit |
|----------|---------|------------|
| `POST /search` | Semantic web search | 5 QPS |
| `POST /contents` | Get page contents | 50 QPS |
| `POST /findSimilar` | Find similar pages | 5 QPS |
| `POST /answer` | AI answer with citations | 5 QPS |

## Configuration

API key is **required**.

```bash
# Single API key
export EXA_API_KEY="your-key-here"

# Multiple API keys for load distribution
export EXA_API_KEY="key1,key2,key3"
```

When multiple keys are provided (comma-separated), the script rotates through them in round-robin order, ensuring even distribution of requests. If a key hits rate limits (429), the script automatically fails over to the next key and retries, only failing after all keys are exhausted across multiple retry rounds.

Get an API key at [dashboard.exa.ai](https://dashboard.exa.ai/api-keys).

## Requirements

- **Platforms**: Linux, macOS
- **Dependencies**: bash, curl, jq

## Skill Metadata

```yaml
name: exa
description: Searches the web using Exa's neural embeddings-based search API. Use when needing real-time web information to answer questions, verify facts, debug issues, find code examples, research topics, or clear doubts with authoritative sources.
```

## License

MIT License
