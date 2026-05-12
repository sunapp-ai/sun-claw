# Sun to Spotify

Turn any topic, question, or feed into a **dialogue podcast** — and listen to it in Spotify or your favorite podcast app.

Just say:

> What's the latest in voice and audio AI? Give me a 10-minute roundup.

> What's happening in the stock market this morning? Make it a 5-minute brief.

> Give me my daily brief based on my calendar for the next 30 minutes.

> Summarize *The Hard Thing About Hard Things* as a 20-minute podcast.

> How should I think about marketing my B2B startup? Give me a 15-minute deep dive.

[Sun](https://sunapp.ai) handles everything: research, script writing, multi-speaker dialogue, audio mixing, and publishing. The result lands in your Spotify library, ready to play from any device.

---

## Quick Start

### 1. Install the CLI

Prompt your agent to install the CLI:

> Install the Sun CLI by running https://sunapp-ai.github.io/sun-to-spotify/install.sh

Or install manually:

```bash
curl -fsSL https://sunapp-ai.github.io/sun-to-spotify/install.sh | bash
```

The installer picks the first available Python package manager — `uv` (preferred), then `pipx`, then `pip --user` — and installs [`sun-cli`](https://pypi.org/project/sun-cli/) from PyPI. Python 3.10+ required.

```bash
uv tool install 'sun-cli>=0.2.0'   # manual: places sun at ~/.local/bin/sun
pipx install 'sun-cli>=0.2.0'      # isolated venv
pip  install 'sun-cli>=0.2.0'      # standard install
```

### 2. Install the skill

The `sun-to-spotify` skill teaches Claude Code how to drive the CLI. Drop it into your Claude Code skills directory:

```bash
# Project-scoped (only available inside this repo)
git clone https://github.com/sunapp-ai/sun-to-spotify .claude/skills/sun-to-spotify

# User-scoped (available in every project)
git clone https://github.com/sunapp-ai/sun-to-spotify ~/.claude/skills/sun-to-spotify
```

Claude Code picks up the skill on the next session.

### 3. Authenticate

```bash
sun login
```

Opens your browser to sign in or create a free account. One-time for typical use — the CLI caches credentials; tokens refresh automatically. For CI or headless hosts, set `SUN_TOKEN` or copy credentials from a machine where you ran `sun login` once (see [references/cli-usage.md](references/cli-usage.md)).

```bash
sun whoami    # check who's logged in
sun logout    # forget cached session
```

### 4. Ask for whatever you want to hear

The skill handles generation, polling, and download automatically — login, job creation, status checks, and saving the manifest plus per-segment MP3s locally.

### 5. Save to Spotify

When generation finishes, the skill can offer to publish your podcast to Spotify. Install the [`save-to-spotify`](https://github.com/spotify/save-to-spotify) skill or CLI. That path is upload-only (Sun already produced the audio); for richer Spotify packaging (cover art, in-player timeline, and so on), use `save-to-spotify` directly.

---

## Personal API tokens

```bash
sun tokens create <name>    # mint a token (name: ^[a-z0-9-]+$, 1-64 chars)
sun tokens list
sun tokens revoke <name>
```

The full secret is printed once at creation. Token shape: `sk_live_<22-char-base32>_<32-char-base32>`.

---

## CLI reference

| Command | What it does |
| --- | --- |
| `sun login` | Sign in via browser |
| `sun whoami` | Check who's logged in |
| `sun logout` | Forget cached session |
| `sun tokens create <name>` | Mint a personal API token |
| `sun tokens list` | List your tokens |
| `sun tokens revoke <name>` | Revoke a token |
| `sun courses create` | Start a podcast generation job |
| `sun courses status <id>` | Check job status (`PENDING`, `PROCESSING`, `SUCCESS`, `ERROR`) |
| `sun courses get <id>` | Print manifest or download finished audio |

### `courses create` flags

| Flag | Description |
| --- | --- |
| `--prompt TEXT` | What to generate (1-4000 chars) |
| `--input PATH` | Read prompt from a file |
| `--duration-minutes N` | Length in minutes (5-120, default 30) |
| `--voice-id UUID` | Optional voice override |
| `--wait` | Block until done |
| `--json` | Machine-readable JSON output |

### `courses get`

```bash
sun courses get <JOB_ID>              # manifest JSON to stdout
sun courses get <JOB_ID> --out ./dir  # manifest + segment MP3s
```

Signed segment URLs are re-signed on each fetch — do not cache `audio_url` values long-term.

### JSON mode

Every command supports `--json` for scripting. Errors emit `{"error": {"code": "...", "message": "..."}}` and a non-zero exit. See [references/cli-usage.md](references/cli-usage.md) for exit codes and troubleshooting.

---

## Environment variables

| Variable | Purpose |
| --- | --- |
| `SUN_TOKEN` | API token for CI / non-interactive use (overrides the credentials file) |

---

## Error codes (quick)

| HTTP | `error.code` | Meaning |
| --- | --- | --- |
| 401 | `unauthorized` | Missing / invalid / revoked token |
| 403 | `forbidden` | Anonymous user trying to mint a token — complete email login |
| 404 | `not_found` | Wrong id or not your resource |
| 409 | `conflict` / `not_ready` | Duplicate token name, or `get` before `SUCCESS` |
| 422 | `validation_error` | Fix request body |
| 429 | `rate_limit_exceeded` | Respect `Retry-After` |
| 500 | `internal_error` | Safe to retry with backoff |

Read `error.code`, not only HTTP status (409 covers multiple cases).

---

## Repository layout

- [`SKILL.md`](SKILL.md) — skill entry point for Claude Code
- [`references/cli-usage.md`](references/cli-usage.md) — full CLI reference
- [`references/http-api.md`](references/http-api.md) — HTTP API when you are not using the CLI
- [`install.sh`](install.sh) — curl installer (hosted via GitHub Pages)

---

## Links

- [Sun](https://sunapp.ai)
- [sun-cli on PyPI](https://pypi.org/project/sun-cli/)
- [Claude Code](https://claude.com/claude-code)
- [Save to Spotify](https://github.com/spotify/save-to-spotify)
