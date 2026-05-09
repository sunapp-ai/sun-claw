# Sun CLI Usage

Reference for the `sun` CLI: install, authentication, commands, flags, JSON mode, error handling, and common end-to-end workflows.

The CLI is the recommended path. For HTTP-only flows see [http-api.md](http-api.md).

## Installation

The `sun` CLI is self-contained — it ships and works independently of the monorepo. PyPI package name is `sun-cli`; the installed binary is `sun`. Once installed, `sun` is available on `PATH` from any directory.

### Curl installer (recommended)

```bash
curl -fsSL https://sunapp-ai.github.io/sun-to-spotify/install.sh | bash
```

The installer picks the first available Python package manager — `uv` (preferred), then `pipx`, then `pip --user` — and installs `sun-cli` from PyPI. If none of those is on `PATH`, the script prints install instructions and exits 1; install one and re-run.

### uv tool install

If the user already has [uv](https://docs.astral.sh/uv/):

```bash
uv tool install 'sun-cli>=0.2.0'
```

This places `sun` on `PATH` (`~/.local/bin` by default) without requiring a project venv. Update with `uv tool upgrade sun-cli`.

### pip / pipx

Standard Python install:

```bash
pip install 'sun-cli>=0.2.0'
# or, isolated:
pipx install 'sun-cli>=0.2.0'
```

Python 3.10+ required. Only two runtime deps: `httpx` and `typer`.

### Verify

```bash
sun --help
sun version       # if available
```

macOS and Linux are first-class. Windows works for the HTTP calls but the credentials file relies on user-directory ACL, not `chmod 0600`.

### Monorepo dev install (internal contributors only)

For working on the CLI itself from inside the `sun-monorepo` checkout:

```bash
uv sync                    # install project dependencies into the venv
uv run sun --help          # invoke the dev build
```

External users do **not** need this; they should use one of the install methods above and run `sun ...` directly. The `uv run sun ...` form only applies inside the monorepo.

If `sun --help` fails after a fresh install, the most common causes are:
- The install dir isn't on `PATH` — check `echo $PATH` and re-source the shell rc.
- The install partially failed — re-run the installer.
- A previous version is shadowing the new one — `which -a sun` to find duplicates.

## Authentication

### Two auth flows

| Endpoint family | Auth | Header |
| --- | --- | --- |
| Token management (`POST/GET/DELETE /v1/public/tokens*`) | Supabase JWT | `Authorization: Bearer <jwt>` |
| Everything else (`/v1/public/courses*`, `/v1/public/whoami`) | Personal API token | `Authorization: Bearer sk_live_...` |

Token-management endpoints reject API-token auth on purpose: a leaked API token cannot mint replacements.

### `sun login` — Supabase login

```bash
sun login                                # opens browser, loopback POST handoff
sun logout                               # forget cached session + saved tokens
sun whoami                               # prints email, user_id, active token name
```

`sun login` opens the user's browser to `https://sunapp.ai/login`, where they can sign in with email + password, create a new account, or reset a forgotten password via the **"Forgot your password?"** link. The webapp posts the resulting Supabase session to a loopback listener the CLI binds; tokens never appear in any URL.

For new accounts, the flow is two-step: the first `sun login` only registers the account and triggers the confirmation email. After clicking the link in the email, the user must start a **fresh `sun login`** session and sign in with the new account on the Sign-in tab — the original loopback does not auto-complete after email confirmation.

The browser flow is the only supported way to log in. There is no `--email`/`--password` or `--no-browser` fallback; headless and CI environments need to authenticate on a machine with a browser first, then carry the resulting credentials file or `SUN_TOKEN` over.

The CLI fetches the Supabase URL and anon key automatically from the public `auth-config` endpoint. The refresh token is persisted at `~/.config/sun/credentials.json` with mode `0600` on Unix.

> Verify the exact env-var names with `sun --help`. The CLI is the source of truth — older docs may use different names.

### `sun tokens` — personal API tokens

```bash
sun tokens create NAME             # prints secret to stdout, saves as active
sun tokens create NAME --no-save   # prints, does not save (CI: capture into a var)
sun tokens list
sun tokens revoke NAME|ID
```

Token shape: `sk_live_<22-char-base32>_<32-char-base32>`. The full secret is shown **once** at creation. `NAME` must match `^[a-z0-9-]+$`, 1-64 chars, unique per user.

Revoke is idempotent — revoking the same token twice still returns `204`. Soft-revoked tokens stay visible in `tokens list` (audit trail) but cannot authenticate.

## Generating a course

### `sun courses create`

```bash
sun courses create \
  --prompt "A 30-minute course on the French Revolution" \
  --duration-minutes 30
# Prints the job_id to stdout.

# Or read the prompt from a file / stdin:
sun courses create --input ./prompt.txt
cat ./prompt.txt | sun courses create

# Block until done and print the result:
sun courses create --prompt "..." --wait
# stderr: status updates (PENDING → PROCESSING → SUCCESS)
# stdout: human summary, or full JSON with --json

# Pick a specific voice:
sun courses create --prompt "..." --voice-id <uuid>
```

Flags:

| Flag | Purpose |
| --- | --- |
| `--prompt TEXT` | Course prompt. 1-4000 chars. Mutually exclusive with `--input`/stdin. |
| `--input PATH` | Read prompt from a file. |
| `--duration-minutes N` | 5-120. Default 30. |
| `--voice-id UUID` | Optional voice override. |
| `--wait` | Block until SUCCESS / ERROR. Polls with exponential back-off (2s → 30s cap, total 30 min). |
| `--json` | Emit machine-readable JSON to stdout. |

Exactly one prompt source must be provided (`--prompt`, `--input`, or stdin when stdin is not a TTY). Otherwise the CLI errors out.

`--wait` exit codes:
- `0` on `SUCCESS`
- non-zero on `ERROR` or 30-min timeout

### `sun courses status`

```bash
sun courses status <JOB_ID>
sun courses status <JOB_ID> --json
```

Returns the lightweight status payload. Always `200`, even when the job is in `ERROR` (the error sits inside the body, not the status code).

Recommended manual cadence when not using `--wait`: first poll at 5s, then exponential back-off capped at 30s. Typical 30-min course completes in **60-300s**.

### `sun courses get`

```bash
sun courses get <JOB_ID>                    # JSON manifest to stdout
sun courses get <JOB_ID> --json             # same; explicit
sun courses get <JOB_ID> --out ./my-course  # download into a directory
```

`--out DIR` writes:

```
DIR/course.json                        # the manifest
DIR/lectures/001-<slug>.mp3
DIR/lectures/002-<slug>.mp3
...
```

Lectures whose `audio_url` is `null` (still uploading, transient storage error) are skipped with a stderr warning. **Re-run the same command** to fetch fresh signed URLs and pick up missing files. The result endpoint re-signs URLs on every read.

`409 not_ready` appears if the job hasn't reached `SUCCESS` yet — wait and retry.

## JSON mode

For agents, always pass `--json`:

```bash
sun --json courses status <JOB_ID>
sun courses create --prompt "..." --json
```

Note: some commands accept `--json` as a global flag (before the subcommand), others as a subcommand flag. Both work in current builds — when in doubt, run `sun --help` or `sun courses create --help`.

In JSON mode:
- All structured output is JSON on stdout.
- Errors emit the bare error envelope: `{"error": {"code": "...", "message": "...", ...}}` and exit non-zero.
- Status updates and progress hints go to stderr (suppressible by redirecting `2>/dev/null`).

## Configuration / env vars

| Variable | Purpose |
| --- | --- |
| `SUN_TOKEN` | Use this API token instead of the credentials file (CI mode). Takes precedence over `~/.config/sun/credentials.json`. |

Confirm the exact names against `sun --help` if the CLI has been rebuilt — env-var names are the most likely thing to drift in the rename.

## Error codes

| HTTP | `error.code` | Meaning | Action |
| --- | --- | --- | --- |
| 401 | `unauthorized` | Missing / malformed / unknown / revoked token | `tokens list`, mint a new one, or `login` again |
| 403 | `forbidden` | Anonymous Supabase user trying to mint a token | `login` with email + password |
| 404 | `not_found` | Resource doesn't exist OR is owned by another user | Verify the job/token id |
| 409 | `conflict` | Duplicate token name on `tokens create` | Pick a different name |
| 409 | `not_ready` | `courses get` while job not yet `SUCCESS` | Poll status; retry |
| 422 | `validation_error` | Body failed schema validation | Read `error.details`; fix the request |
| 429 | `rate_limit_exceeded` | Per-user 24h cap reached | Read `Retry-After`; ask user before waiting |
| 500 | `internal_error` | Server-side failure | Safe to retry with back-off |

Both `409 conflict` and `409 not_ready` share the HTTP status — always read `error.code`, not just the status.


## Common workflows

### Mint token + generate + download (fresh user)

```bash
sun login
sun tokens create laptop
sun courses create \
  --prompt "A 30-minute course on the French Revolution" \
  --duration-minutes 30 \
  --wait
# read JOB_ID from the --wait output, or from --json
sun courses get <JOB_ID> --out ./french-revolution
```

### Generate-and-download (existing token, headless)

```bash
export SUN_TOKEN="sk_live_..._..."

JOB=$(sun courses create --prompt "..." --json | jq -r .job_id)

while true; do
  S=$(sun courses status "$JOB" --json | jq -r .status)
  case "$S" in
    SUCCESS) break ;;
    ERROR)   sun courses status "$JOB" --json | jq -r .error; exit 1 ;;
    *)       sleep 10 ;;
  esac
done

sun courses get "$JOB" --out ./out
```


## Troubleshooting

### `Logged in as ...` but `tokens list` returns 401

Supabase session expired. Run `sun login` again. If the credentials file was edited or the password changed, the refresh path may fail.

### `401 unauthorized` with an API token that worked yesterday

The token may have been revoked. Run `sun tokens list` — revoked tokens show as `[REVOKED]`. Mint a new one.

### `429` even though I haven't hit my limit

Window is rolling 24h, not calendar day. A request at 23:00 yesterday still counts until 23:00 today. `X-RateLimit-Reset` and `Retry-After` are authoritative. Web-app and voice-agent generations do **not** count toward the public-API quota — only public-API requests do.

### Job stuck in `PENDING` for >60s

Worker saturation. Public-API requests share concurrency with the rest of the platform. The job will pick up when a slot frees; this isn't a 503. Keep polling.

### `409 not_ready` even though status shows `SUCCESS`

Briefly possible during the worker's commit window. Wait 1-2 seconds and retry the result endpoint.

### `audio_url` is `null` after `SUCCESS`

The lecture audio file hasn't propagated to storage yet, or there's a transient storage error for that lecture. Re-fetch the result endpoint to refresh signed URLs and try again. `courses get --out` already does this — re-run the same command.

### `login` prints "wrong email or password"

Run `login` again with the correct credentials. If the password is forgotten, run `sun login` (browser flow) and click **"Forgot your password?"** on the /login page to send a reset email; complete the reset on the web, then re-run `sun login`.

### `login` prints "the server's auth config is invalid"

Server-side misconfiguration, not the user's password. Surface the error to the user; don't retry.

### CLI hangs / connection times out

Check `SUN_API_BASE_URL`. For local dev set it to `http://127.0.0.1:8000`. For staging vs. production, confirm the deployment URL with the user.

### `--json` gives unexpected shape

Some subcommands accept `--json` globally (`sun --json courses status ...`), others as a flag on the subcommand (`sun courses status --json ...`). Both forms exist in current builds; if one doesn't parse, try the other. `sun courses create --help` shows the supported placement.
