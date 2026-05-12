# sun-to-spotify

A [Claude Code](https://claude.com/claude-code) skill — and a public reference for the [`sun`](https://pypi.org/project/sun-cli/) CLI — for generating [Sun](https://sunapp.ai) audio experiences programmatically. Hand it a topic and a duration and it produces a finished **podcast, audiobook, or audio course** you can download or publish. Built for agents and automation.

## Quick Start

Prompt your agent to install the CLI:

```text
> Install the Sun CLI by running https://sunapp-ai.github.io/sun-to-spotify/install.sh
```

Then drop the `sun-to-spotify` skill into your Claude Code skills directory (see [Install the skill](#install-the-skill)).

Once installed, ask for whatever audio format fits:

> Make me a 20-minute podcast on the history of the printing press.
> Read me a 45-minute audiobook chapter about the Stoics.
> Build a 60-minute audio course on linear algebra fundamentals.

The skill drives the CLI end-to-end — login, generation, polling, download — and saves the manifest plus per-segment MP3s into a local directory.

## Install

### Curl-bash

```bash
curl -fsSL https://sunapp-ai.github.io/sun-to-spotify/install.sh | bash
```

The installer picks the first available Python package manager — `uv` (preferred), then `pipx`, then `pip --user` — and installs `sun-cli` from PyPI. If none is on `PATH`, the script prints install instructions and exits 1.

### uv tool (manual)

```bash
uv tool install 'sun-cli>=0.2.0'
```

Places `sun` at `~/.local/bin/sun`. Update with `uv tool upgrade sun-cli`.

### pipx / pip

```bash
pipx install 'sun-cli>=0.2.0'      # isolated venv
pip  install 'sun-cli>=0.2.0'      # standard install
```

Python 3.10+ required. Two runtime deps: `httpx` and `typer`.

### Install the skill

The `sun-to-spotify` skill teaches Claude Code how to drive the CLI. Drop it into your Claude Code skills directory:

```bash
# Project-scoped (only available inside this repo)
git clone https://github.com/sunapp-ai/sun-to-spotify .claude/skills/sun-to-spotify

# User-scoped (available in every project)
git clone https://github.com/sunapp-ai/sun-to-spotify ~/.claude/skills/sun-to-spotify
```

Claude Code picks up the skill on the next session.

## Authentication

`sun-cli` ships a browser-based login flow. `sun login` opens your browser to `https://sunapp.ai/login`, where you can sign in with email + password, create a new account, or reset a forgotten password via the **"Forgot your password?"** link. The webapp posts the resulting Supabase session straight to a loopback listener the CLI binds — tokens never appear in any URL, browser history, or server log.

```bash
# Opens browser, loopback POST handoff
sun login

# Check who's logged in (and which token is active)
sun whoami

# Forget the cached session and saved tokens
sun logout
```

Browser login is the only supported mode. There is no `--email`/`--password` or `--no-browser` fallback. If you need to use `sun` from a CI / SSH / headless environment, run `sun login` once on a machine with a browser and copy the resulting `~/.config/sun/credentials.json` over (or mint a `SUN_TOKEN` and set the env var on the headless side).

Credentials are stored at `~/.config/sun/credentials.json` (mode `0600` on Unix). The cached refresh token survives terminal restarts; you only re-authenticate when the refresh token itself expires or you run `sun logout`.

### First time? Account states the login flow handles

- **No account yet** → the `/login` page has a Sign-up tab. Email + password, then click the confirmation link Supabase emails you on the same machine where `sun login` is still running. The original loopback completes automatically — no need to re-run `sun login`.
- **Account exists** → email + password sign-in on the Sign-in tab.
- **Forgot password** → click **"Forgot your password?"** on `/login`, click the reset link Supabase emails you on the same machine where `sun login` is still running, set a new password, and the loopback completes automatically — no need to re-run `sun login`.

### Personal API tokens

The `sun` CLI signs generation requests with a personal API token, minted from your Supabase session.

```bash
# Create a new token (NAME must match ^[a-z0-9-]+$, 1-64 chars)
sun tokens create laptop

# List tokens (revoked tokens stay visible for audit; full secret never re-shown)
sun tokens list

# Revoke a token by name or id
sun tokens revoke laptop
```

The full secret is printed **once** at creation, then stored as the active token. Token shape: `sk_live_<22-char-base32>_<32-char-base32>`.

## Commands

### courses create

Submit an audio-generation job. The subcommand is named `courses` because that's the CLI's command, but the output can be a podcast, audiobook, or audio course depending on the prompt.

```bash
sun courses create \
  --prompt "A 30-minute podcast on the French Revolution" \
  --duration-minutes 30
# Prints the job_id to stdout.

# Read the prompt from a file or stdin
sun courses create --input ./prompt.txt
cat ./prompt.txt | sun courses create

# Block until done (polls with exponential back-off, 30 min total timeout)
sun courses create --prompt "..." --wait

# Pick a specific voice
sun courses create --prompt "..." --voice-id <uuid>
```

| Flag | Description |
|---|---|
| `--prompt TEXT` | Audio prompt — the topic for the podcast / audiobook / audio course. 1-4000 chars. Mutually exclusive with `--input`/stdin. |
| `--input PATH` | Read prompt from a file. |
| `--duration-minutes N` | 5-120. Default 30. |
| `--voice-id UUID` | Optional voice override. |
| `--wait` | Block until SUCCESS / ERROR. |
| `--json` | Emit machine-readable JSON. |

### courses status

Check whether a job has finished.

```bash
sun courses status <JOB_ID>
sun courses status <JOB_ID> --json
```

Statuses: `PENDING`, `PROCESSING`, `SUCCESS`, `ERROR`. Always returns `200` — read the body, not the status code. A typical 30-minute audio program completes in **60-300s**.

### courses get

Download the manifest and segment MP3s.

```bash
# Print the JSON manifest to stdout
sun courses get <JOB_ID>

# Download into a directory
sun courses get <JOB_ID> --out ./my-audio
```

`--out DIR` writes (the manifest filename and `lectures/` subdir are produced by the CLI — those are stable disk paths, not the user-facing framing):

```
DIR/course.json
DIR/lectures/001-<slug>.mp3
DIR/lectures/002-<slug>.mp3
...
```

Signed audio URLs are re-signed on every read of the result endpoint, so re-running `courses get` will fetch fresh URLs and fill in any segments that were skipped due to upload lag. **Don't cache `audio_url` values yourself.**

## JSON mode

Every command supports `--json` for scripting:

```bash
JOB_ID=$(sun courses create --prompt "..." --json | jq -r .job_id)
sun --json courses status "$JOB_ID" | jq -r .status
```

In JSON mode:
- All structured output goes to stdout.
- Errors emit the bare envelope `{"error": {"code": "...", "message": "..."}}` and exit non-zero.
- Status updates and progress hints go to stderr.

## Save to Spotify (optional)

If you also have the [`save-to-spotify`](https://github.com/spotify/save-to-spotify) Claude Code skill or CLI installed, sun-to-spotify will offer to publish the generated audio to Spotify as a podcast after generation finishes.

The integration is **strictly auth + upload**:

- `save-to-spotify auth status` / `auth login`
- `save-to-spotify shows` / `shows create`
- `save-to-spotify upload` (one episode per segment, in order)
- `save-to-spotify episodes status` (poll until `READY`)

sun-to-spotify does **not** invoke save-to-spotify's content-production pipeline — no TTS, no script writing, no cover-image generation, no timeline production. The audio is already produced by `sun`; Spotify just hosts it.

If you want a richer Spotify production (custom cover, image companions, in-player timeline), skip the prompt and use the `save-to-spotify` skill directly.

## Environment variables

| Variable | Purpose |
|---|---|
| `SUN_TOKEN` | Use this API token instead of the credentials file (CI mode). Takes precedence over `~/.config/sun/credentials.json`. |

## Error codes

| HTTP | `error.code` | Meaning | Action |
|---|---|---|---|
| 401 | `unauthorized` | Missing / unknown / revoked token | `tokens list`, mint a new one, or `login` again |
| 403 | `forbidden` | Anonymous Supabase user trying to mint a token | `login` with email + password |
| 404 | `not_found` | Resource doesn't exist or is owned by another user | Verify the job/token id |
| 409 | `conflict` / `not_ready` | Duplicate token name, or `courses get` before `SUCCESS` | Pick a new name; or wait and retry |

| 422 | `validation_error` | Body failed schema validation | Read `error.details` and fix the request |
| 429 | `rate_limit_exceeded` | Per-user 24h cap reached | Read `Retry-After`; ask user before waiting |
| 500 | `internal_error` | Server-side failure | Safe to retry with back-off |

Both `409` codes share the HTTP status — always read `error.code`, not just the status.

## Layout

- [`SKILL.md`](SKILL.md) — skill entry point loaded by Claude Code.
- [`references/cli-usage.md`](references/cli-usage.md) — full `sun` CLI reference (commands, flags, exit codes, troubleshooting).
- [`references/http-api.md`](references/http-api.md) — HTTP-only flow when the CLI isn't available.
- [`install.sh`](install.sh) — the curl installer, hosted via GitHub Pages.

## Links

- Sun — https://sunapp.ai
- `sun-cli` on PyPI — https://pypi.org/project/sun-cli/
- Claude Code — https://claude.com/claude-code
- Save to Spotify — https://github.com/spotify/save-to-spotify
