# sun-claw

A [Claude Code](https://claude.com/claude-code) skill for generating [Sun](https://sunapp.ai) audio courses programmatically.

Given a prompt and a target duration, the skill drives the `sun` CLI (or the public HTTP API) to:

1. Authenticate and mint a personal API token.
2. Create a course generation job.
3. Poll until the job finishes.
4. Download the manifest and per-lecture MP3 files.

## Install

Drop the skill into your Claude Code skills directory — either project-scoped or user-scoped:

```bash
# Project-scoped (only available inside this repo)
git clone https://github.com/sunapp-ai/sun-claw .claude/skills/sunclaw

# User-scoped (available in every project)
git clone https://github.com/sunapp-ai/sun-claw ~/.claude/skills/sunclaw
```

Claude Code picks up the skill on the next session.

## Prerequisite — the `sun` CLI

The skill drives the [`sun`](https://pypi.org/project/sun-cli/) CLI. Install it once:

```bash
# Recommended
uv tool install sun-cli

# Or
pip install sun-cli
pipx install sun-cli
```

The PyPI package is `sun-cli`; the installed binary is `sun`.

If the CLI isn't installable in your environment, the skill falls back to the HTTP API — see [`references/http-api.md`](references/http-api.md).

## Usage

Once installed, ask Claude something like:

> Make me a 20-minute course on the history of the printing press.

Claude will invoke the `sunclaw` skill, run `sun login` if needed, create the course, poll until it's ready, and save the manifest plus MP3s to a local directory.

## Layout

- [`SKILL.md`](SKILL.md) — skill entry point. Loaded by Claude Code when the skill is triggered.
- [`references/cli-usage.md`](references/cli-usage.md) — `sun` CLI reference (commands, flags, exit codes, troubleshooting).
- [`references/http-api.md`](references/http-api.md) — HTTP-only flow when the CLI isn't available.

## Links

- Sun — https://sunapp.ai
- `sun` CLI on PyPI — https://pypi.org/project/sun-cli/
- Claude Code — https://claude.com/claude-code
