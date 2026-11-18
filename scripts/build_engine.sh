#!/bin/bash
# Builds Conclave's engine (the Python backend the Windows app ships) for this Mac, from the Conclave commit in
# conclave.rev, into build/engine/conclave-backend/. Needs uv (`brew install uv`) and git.
#
#   scripts/build_engine.sh            # once, and again after changing conclave.rev
#   CONCLAVE_SRC=~/code/Conclave scripts/build_engine.sh   # from your own Conclave checkout instead
set -euo pipefail
cd "$(dirname "$0")/.."
rev=$(tr -d '[:space:]' < conclave.rev)
out=build/engine
src=${CONCLAVE_SRC:-build/conclave}

if [ -z "${CONCLAVE_SRC:-}" ]; then
  if [ ! -d "$src/.git" ]; then
    git clone --quiet https://github.com/liehrdot/Conclave.git "$src"
  fi
  git -C "$src" fetch --quiet --depth 1 origin "$rev"
  git -C "$src" checkout --quiet --force "$rev"
fi

echo "Building the engine from Conclave $(git -C "$src" rev-parse --short HEAD)"
(cd "$src" && uv sync --quiet --extra gui --extra desktop && uv run pyinstaller --noconfirm --clean --log-level WARN desktop/sidecar/backend.spec)
rm -rf "$out"
mkdir -p "$out"
cp -R "$src/dist/conclave-backend" "$out/"
echo "$rev" > "$out/conclave.rev"
echo "Engine ready: $out/conclave-backend ($(du -sh "$out/conclave-backend" | cut -f1))"
