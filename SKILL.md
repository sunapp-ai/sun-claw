---
id: sunclaw
name: sunclaw
description: Generate Sun audio courses programmatically. Uses the `sun` CLI (or HTTP API) to authenticate, mint a personal API token, create a course from a prompt, poll until ready, and download the manifest plus per-lecture MP3 files.
enabled: true
---

# Sunclaw — Sun Course Generation Skill

`sunclaw` produces audio courses through the Sun public API. Given a prompt and a target duration, it creates a course, waits for generation to finish, and saves the manifest plus per-lecture MP3 files locally.

The skill is built around the `sun` CLI — a self-contained binary that ships independently of the monorepo. For environments where the CLI isn't available, the same flow can run directly against the HTTP API.

## Reference Directory

Load only the file you need — don't inline them.

- [references/cli-usage.md](references/cli-usage.md) — `sun` CLI commands: `login`, `whoami`, `tokens`, `courses`. Install methods, flags, exit codes, JSON mode, env-var overrides, troubleshooting.
- [references/http-api.md](references/http-api.md) — HTTP-only flow when the CLI isn't installed: `auth-config` discovery, Supabase password grant, token mint, course create / status / result, signed-URL audio download, rate-limit headers, error envelope.

---

## Install

The `sun` CLI is independently installable — no monorepo checkout required. Three options, in order of recommendation for external users:

```bash
# 1. uv tool (recommended)
uv tool install sun-cli

# 2. pip
pip install sun-cli

# 3. pipx (isolated)
pipx install sun-cli
```

Verify:

```bash
sun --help
```

> PyPI package name is `sun-cli`; the installed binary is `sun`. (A shell installer at `https://sunapp.ai/install.sh` is planned but not yet available — use one of the Python-based methods above for now.)

If `sun --help` fails after install, ask the user how they installed it before troubleshooting. See [references/cli-usage.md](references/cli-usage.md) for monorepo-dev install (`uv sync` + `uv run sun`) and platform-specific notes.

---

## Core Principles

### Inputs come from the user

Don't invent a prompt. If the user said "make a course about X", that's the prompt. If they didn't supply one, ask. Never substitute a creative prompt of your own.

### Save incrementally

Write the `job_id` to disk (or echo it back to the user) immediately after the `202` response. If polling crashes mid-loop, the job keeps generating server-side — re-poll with the same `job_id` rather than restarting.

### Don't cache signed URLs

`audio_url` values are signed for 7 days, but the result endpoint re-signs them on every read. Always fetch fresh URLs from `/v1/public/courses/{job_id}` right before downloading; never persist them.

### Surface server-reported errors verbatim

The API returns a bare `{"error": {"code": "...", "message": "...", ...}}` envelope on every non-2xx. When something fails, show the user the `error.message` and `error.code` — don't paraphrase or hide them. For `429`, read `Retry-After` instead of computing waits yourself.

---

## Required Inputs

Before generating, confirm the user has supplied:

1. **Prompt** — the course topic. 1-4000 chars. Mandatory.
2. **Duration** — minutes of audio. 5-120, default 30. Optional.
3. **Voice** — voice UUID. Optional. If not given, the API picks a default.
4. **Output directory** — where to save the downloaded MP3s. Optional; default to `./course-<short-job-id>/`.

If the prompt is missing, ask once and stop. Don't proceed without it.

---

## Execution Checklist

Run these in order. Do not skip preflight.

### 0. Preflight — CLI presence and auth

```bash
sun --help              # verify the CLI is on PATH and runnable
sun whoami              # verify there's an active session + token
```

- If `sun --help` fails, the CLI isn't installed. Show the user the Install section above and ask them to confirm before running the installer. If install isn't possible, fall back to the HTTP flow in [references/http-api.md](references/http-api.md).
- If `whoami` reports unauthenticated, run `sun login` (will prompt for email + password).
- If `whoami` reports authenticated but no active token, run `sun tokens create <name>` (`<name>` matches `^[a-z0-9-]+$`, 1-64 chars). The full secret prints to stdout once and is stored as the active token; surface it to the user but never log it elsewhere.

### 1. Create the course

```bash
sun courses create \
  --prompt "<the user's prompt>" \
  --duration-minutes <N> \
  --wait
```

- `--wait` blocks until `SUCCESS` or `ERROR` and prints status updates to stderr. Total timeout is 30 min.
- Without `--wait`, the command prints the `job_id` immediately and returns; you must poll yourself (see step 2).
- Pass `--voice-id <uuid>` if the user specified a voice.
- Pass the prompt via `--input <path>` or stdin if it's longer than a comfortable shell argument.

A `429` response means the user hit their daily limit. Show them `error.message`, `Retry-After`, and `X-RateLimit-Reset`. Do not auto-retry.

### 2. Poll for completion (only if `--wait` wasn't used)

```bash
sun courses status <JOB_ID>
```

Cadence: first poll at 5s, then exponential back-off capped at 30s. Typical 30-min course completes in **60-300s**. Total timeout 30 min.

Treat statuses as:
- `PENDING` / `PROCESSING` → keep polling
- `SUCCESS` → proceed to step 3
- `ERROR` → surface `error.message` and `error.retryable`. If `retryable: true`, ask the user before re-creating.

### 3. Download the course

```bash
sun courses get <JOB_ID> --out <output-dir>
```

Writes:
```
<output-dir>/course.json
<output-dir>/lectures/001-<slug>.mp3
<output-dir>/lectures/002-<slug>.mp3
...
```

If any lecture's `audio_url` is `null` (storage propagation lag), the CLI skips it with a stderr warning. Re-run the same command — the result endpoint re-signs URLs and fills in missing files.

### 4. Verify

Confirm the manifest exists and the lecture count matches `course.json`'s `lectures[]`:

```bash
test -f <output-dir>/course.json && \
  jq -r '.lectures | length' <output-dir>/course.json
ls <output-dir>/lectures/ | wc -l
```

If the counts disagree, re-run step 3 once. If they still disagree, surface the gap to the user — don't loop indefinitely.

---

## End-to-end example

A complete generation for a user request "Make me a 20-minute course on the history of the printing press":

```bash
sun --help >/dev/null || { echo "CLI not installed"; exit 1; }
sun whoami || sun login

JOB_ID=$(sun courses create \
  --prompt "The history of the printing press" \
  --duration-minutes 20 \
  --json \
  | jq -r .job_id)
echo "job_id: $JOB_ID"

while true; do
  S=$(sun courses status "$JOB_ID" --json | jq -r .status)
  case "$S" in
    SUCCESS) break ;;
    ERROR)   echo "generation failed"; exit 1 ;;
    *)       sleep 10 ;;
  esac
done

sun courses get "$JOB_ID" --out ./printing-press
ls ./printing-press/lectures/
```



---

## When the CLI isn't available

If `sun` isn't installable (sandboxed env, restricted shell, etc.), the HTTP API supports the same operations. See [references/http-api.md](references/http-api.md) — it covers `auth-config` discovery, the Supabase password grant for token minting, course create / status / result, and the audio-download loop in pure curl or `httpx`.
