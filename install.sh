#!/usr/bin/env bash
# Install the Sun CLI (sun-cli) from PyPI.
#
# Usage:
#   curl -fsSL https://sunapp-ai.github.io/sun-to-spotify/install.sh | bash
#
# Installs the `sun-cli` package using whichever Python package manager is
# available, in this order: uv (preferred), pipx, pip. The installed binary
# is named `sun`.

set -euo pipefail

PACKAGE="sun-cli>=0.2.1"
BINARY="sun"

err()  { printf 'error: %s\n' "$*" >&2; }
info() { printf ':: %s\n' "$*"; }
ok()   { printf 'ok: %s\n' "$*"; }

if command -v uv >/dev/null 2>&1; then
  info "Installing $PACKAGE with uv..."
  uv tool install "$PACKAGE"
elif command -v pipx >/dev/null 2>&1; then
  info "Installing $PACKAGE with pipx..."
  pipx install "$PACKAGE"
elif command -v pip >/dev/null 2>&1; then
  info "Installing $PACKAGE with pip --user..."
  pip install --user "$PACKAGE"
else
  err "No Python package manager (uv, pipx, or pip) found on PATH."
  cat >&2 <<'EOF'

Install one of these first, then re-run this installer:

  uv (recommended):
    curl -LsSf https://astral.sh/uv/install.sh | sh

  pipx:
    https://pipx.pypa.io/stable/installation/

  pip:
    https://pip.pypa.io/en/stable/installation/

EOF
  exit 1
fi

if command -v "$BINARY" >/dev/null 2>&1; then
  ok "Installed $PACKAGE. Run: $BINARY --help"
else
  err "$PACKAGE installed, but '$BINARY' is not on PATH."
  cat >&2 <<'EOF'

Add the relevant tool's bin directory to your PATH, then restart your shell:

  uv:    ensure ~/.local/bin is on PATH (or run 'uv tool update-shell')
  pipx:  run 'pipx ensurepath'
  pip:   ensure the user-base bin directory is on PATH (see 'python -m site --user-base')

EOF
  exit 1
fi
