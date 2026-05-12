---
id: sun-to-spotify
name: sun-to-spotify
description: Generate Sun audio experiences — podcasts, audiobooks, or audio courses — programmatically. Uses the `sun` CLI (or HTTP API) to authenticate, mint a personal API token, create an audio program from a prompt, poll until ready, and download the manifest plus per-segment MP3 files.
enabled: true
---

# sun-to-spotify — Sun Audio Generation Skill

`sun-to-spotify` produces audio experiences — podcasts, audiobooks, and audio courses — through the Sun public API. Given a prompt and a target duration, it generates the audio, waits for it to finish, and saves the manifest plus per-segment MP3 files locally.

The skill is built around the `sun` CLI — a self-contained binary that ships independently of the monorepo. For environments where the CLI isn't available, the same flow can run directly against the HTTP API.

> Framing note: when talking to the user, describe the output as a **podcast, audiobook, or audio course** (whichever fits the topic and duration best — short topical takes lean podcast, long narratives lean audiobook, structured multi-segment lessons lean audio course). Avoid framing this as a "course generator" — it's a versatile audio-experience generator.

## Reference Directory

Load only the file you need — don't inline them.

- [references/cli-usage.md](references/cli-usage.md) — `sun` CLI commands: `login`, `whoami`, `tokens`, `courses`. Install methods, flags, exit codes, JSON mode, env-var overrides, troubleshooting.
- [references/http-api.md](references/http-api.md) — HTTP-only flow when the CLI isn't installed: `auth-config` discovery, Supabase password grant, token mint, generation create / status / result, signed-URL audio download, rate-limit headers, error envelope.

---

## Install

The `sun` CLI is independently installable — no monorepo checkout required. Four options, in order of recommendation for external users:

```bash
# 1. curl installer (simplest — picks uv/pipx/pip automatically)
curl -fsSL https://sunapp-ai.github.io/sun-to-spotify/install.sh | bash

# 2. uv tool (manual, fastest)
uv tool install 'sun-cli>=0.2.0'

# 3. pipx (isolated)
pipx install 'sun-cli>=0.2.0'

# 4. pip
pip install 'sun-cli>=0.2.0'
```

Verify:

```bash
sun --help
```

> PyPI package name is `sun-cli`; the installed binary is `sun`. The curl installer is hosted on GitHub Pages from the [`sunapp-ai/sun-to-spotify`](https://github.com/sunapp-ai/sun-to-spotify) repo and requires `uv`, `pipx`, or `pip` to already be available; if none is, it prints install instructions and exits.

If `sun --help` fails after install, ask the user how they installed it before troubleshooting. See [references/cli-usage.md](references/cli-usage.md) for monorepo-dev install (`uv sync` + `uv run sun`) and platform-specific notes.

---

## Core Principles

### Inputs come from the user

Don't invent a prompt. If the user said "make a podcast / audiobook / audio course about X", that's the prompt. If they didn't supply one, ask. Never substitute a creative prompt of your own.

### Save incrementally

Write the `job_id` to disk (or echo it back to the user) immediately after the `202` response. If polling crashes mid-loop, the job keeps generating server-side — re-poll with the same `job_id` rather than restarting.

### Don't cache signed URLs

`audio_url` values are signed for 7 days, but the result endpoint re-signs them on every read. Always fetch fresh URLs from `/v1/public/courses/{job_id}` right before downloading; never persist them.

### Surface server-reported errors verbatim

The API returns a bare `{"error": {"code": "...", "message": "...", ...}}` envelope on every non-2xx. When something fails, show the user the `error.message` and `error.code` — don't paraphrase or hide them. For `429`, read `Retry-After` instead of computing waits yourself.

---

## Required Inputs

Before generating, confirm the user has supplied:

1. **Prompt** — the topic for the audio (podcast, audiobook, or audio course). 1-4000 chars. Mandatory.
2. **Duration** — minutes of audio. 5-120, default 30. Optional.
3. **Voice** — voice UUID. Optional. If not given, the API picks a default.
4. **Output directory** — where to save the downloaded MP3s. Optional; default to `./audio-<short-job-id>/`.

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
- If `whoami` reports unauthenticated: do **not** run `sun login` from the agent. `sun login` opens a browser for the loopback POST handoff — this won't complete in an agent context, and there is no `--email`/`--password` fallback. Ask the user to run `sun login` themselves in their terminal and re-invoke the skill. If the user is signing up for the first time, remind them to click the confirmation email link on the same machine where `sun login` is still running — the original loopback completes automatically post-confirmation, no second `sun login` needed. The same applies to the password-reset flow. For CI / fully non-interactive contexts, the user must first run `sun login` interactively on a machine with a browser, then carry the resulting `~/.config/sun/credentials.json` (or a minted `SUN_TOKEN`) over to the headless environment.
- If `whoami` reports authenticated but no active token, run `sun tokens create <name>` (`<name>` matches `^[a-z0-9-]+$`, 1-64 chars). The full secret prints to stdout once and is stored as the active token; surface it to the user but never log it elsewhere.

### 1. Start the audio generation

The CLI subcommand is `sun courses create` — that's the literal command name; do not rename it. What it produces is an audio program (podcast, audiobook, or audio course depending on the prompt).

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

Cadence: first poll at 5s, then exponential back-off capped at 30s. A typical 30-min audio program completes in **60-300s**. Total timeout 30 min.

Treat statuses as:
- `PENDING` / `PROCESSING` → keep polling
- `SUCCESS` → proceed to step 3
- `ERROR` → surface `error.message` and `error.retryable`. If `retryable: true`, ask the user before re-creating.

### 3. Download the audio

```bash
sun courses get <JOB_ID> --out <output-dir>
```

Writes (the manifest filename and `lectures/` subdir are produced by the CLI — they're stable disk paths, not the user-facing framing):
```
<output-dir>/course.json
<output-dir>/lectures/001-<slug>.mp3
<output-dir>/lectures/002-<slug>.mp3
...
```

If any segment's `audio_url` is `null` (storage propagation lag), the CLI skips it with a stderr warning. Re-run the same command — the result endpoint re-signs URLs and fills in missing files.

### 4. Verify

Confirm the manifest exists and the segment count matches `course.json`'s `lectures[]` array (`lectures` is the JSON field name; the items are segments / episodes / chapters of the produced audio):

```bash
test -f <output-dir>/course.json && \
  jq -r '.lectures | length' <output-dir>/course.json
ls <output-dir>/lectures/ | wc -l
```

If the counts disagree, re-run step 3 once. If they still disagree, surface the gap to the user — don't loop indefinitely.

---

## End-to-end example

A complete generation for a user request "Make me a 20-minute audio program on the history of the printing press" (could equally be phrased "20-minute podcast", "20-minute audiobook chapter", or "20-minute audio course"):

```bash
sun --help >/dev/null || { echo "CLI not installed"; exit 1; }
sun whoami >/dev/null || { echo "Not logged in. Run 'sun login' in your terminal first."; exit 1; }

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

## Optional — Save to Spotify

After step 4, if **either**:

- the [`save-to-spotify`](https://github.com/spotify/save-to-spotify) skill is loaded in this Claude Code session, **or**
- the `save-to-spotify` CLI runs successfully (`save-to-spotify --help`),

ask the user **once**:

> Would you like to publish this to Spotify as a podcast?

If they decline, stop. If they accept, hand off to **only the auth + upload surface** of `save-to-spotify`. sun-to-spotify has already produced the audio — do **not** invoke save-to-spotify's content-production pipeline.

### Strict scope

Use only:
- `save-to-spotify auth status` / `auth login`
- `save-to-spotify shows` / `shows create`
- `save-to-spotify upload` (or `episodes create`)
- `save-to-spotify episodes status` (for readiness polling)

Do **not** invoke save-to-spotify's interview, scripting, TTS, cover-image generation, or timeline production. The MP3s already exist in `<output-dir>/lectures/`; the only job is to authenticate and upload them. If the user wants a rich timeline, image companions, or custom cover generation, defer to the full `save-to-spotify` skill — that's outside sun-to-spotify's scope.

### Inputs to collect

1. **Cover image** — Spotify requires one for new shows. Ask the user for a path. If they don't have one, stop and ask them to supply one before retrying.
2. **Show choice** — list existing shows first; ask whether to publish under an existing show or create a new one. Default name: the `title` field from `course.json`.

### Handoff steps

```bash
# 0. Auth (interactive login on first use)
save-to-spotify --json auth status \
  || save-to-spotify auth login

# 1. Resolve or create the show
save-to-spotify --json shows                              # list existing first
SHOW_URI=$(save-to-spotify --json shows create \
  --title  "$(jq -r .title    <output-dir>/course.json)" \
  --summary "$(jq -r .summary <output-dir>/course.json)" \
  --image  "$COVER" \
  | jq -r .show_uri)

# 2. Upload each segment as an episode, preserving order
jq -c '.lectures[]' <output-dir>/course.json | while read -r L; do
  IDX=$(echo "$L" | jq -r .index)
  TITLE=$(echo "$L" | jq -r .title)
  SUMMARY=$(echo "$L" | jq -r '.summary // .description // ""')
  FILE=$(ls <output-dir>/lectures/$(printf "%03d" "$IDX")-*.mp3)

  EP_URI=$(save-to-spotify --json upload "$FILE" \
    --title   "$TITLE" \
    --summary "$SUMMARY" \
    --show-id "$SHOW_URI" \
    --image   "$COVER" \
    | jq -r .episode_uri)

  # 3. Poll readiness
  until [ "$(save-to-spotify --json episodes status "$EP_URI" | jq -r .readiness)" = "READY" ]; do
    sleep 10
  done
done
```

Adjust the field names (`title`, `summary`, `index`) to match the actual `course.json` schema produced by the `sun` CLI — read the manifest before scripting the loop.

### Error handling

Surface `save-to-spotify` errors verbatim — its JSON envelope already carries `error.code` and `error.message`. Do not auto-retry on `429` or `auth_required`.

---

## When the CLI isn't available

If `sun` isn't installable (sandboxed env, restricted shell, etc.), the HTTP API supports the same operations. See [references/http-api.md](references/http-api.md) — it covers `auth-config` discovery, the Supabase password grant for token minting, generation create / status / result, and the audio-download loop in pure curl or `httpx`.
