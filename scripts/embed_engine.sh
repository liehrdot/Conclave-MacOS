#!/bin/bash
# Xcode build step: copies build/engine/conclave-backend into the app's Contents/Helpers and signs it with the
# app's identity (ad hoc without a Developer account). Without a built engine the app still builds, and its window
# says how to build the engine.
#
# codesign wants only code in Contents/Helpers, and it takes every folder with a dot in its name for a bundle
# ("click-8.5.0.dist-info: bundle format unrecognized"). So, the way PyInstaller lays out its own .app bundles:
# a folder without code moves whole to Contents/Resources/conclave-backend, a loose file that isn't code moves
# alone, and each leaves a relative symlink behind; a folder with code and a dot in its name (python3.12) is
# renamed with __dot__ and keeps its old name as a symlink. The engine sees the same paths as before.
set -euo pipefail
shopt -s nullglob dotglob
engine="$SRCROOT/build/engine/conclave-backend"
contents="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH"
code_root="$contents/Helpers/conclave-backend"
data_root="$contents/Resources/conclave-backend"
if [ ! -x "$engine/conclave-backend" ]; then
  echo "warning: no engine in build/engine – run scripts/build_engine.sh"
  exit 0
fi
rm -rf "$code_root" "$data_root"
mkdir -p "$contents/Helpers"
cp -R "$engine" "$contents/Helpers/"

machos="$(mktemp)"
trap 'rm -f "$machos"' EXIT
while IFS= read -r -d '' f; do
  if file -b "$f" | grep -q "^Mach-O"; then printf '%s\n' "${f#"$code_root"/}" >> "$machos"; fi
done < <(find "$code_root" -type f -print0)

is_code() { grep -qxF -- "$1" "$machos"; }
has_code() { awk -v p="$1/" 'index($0, p) == 1 { found = 1; exit } END { exit !found }' "$machos"; }
# "../" from the folder that holds rel up to Contents
up() {
  local n=2 s="$1" out=""
  while [[ "$s" == */* ]]; do s="${s#*/}"; n=$((n + 1)); done
  while [ "$n" -gt 0 ]; do out="../$out"; n=$((n - 1)); done
  printf '%s' "$out"
}
move_out() {
  mkdir -p "$(dirname "$data_root/$1")"
  mv "$code_root/$1" "$data_root/$1"
  ln -s "$(up "$1")Resources/conclave-backend/$1" "$code_root/$1"
}
walk() {
  local entry rel name
  for entry in "$code_root/${1:+$1/}"*; do
    [ -L "$entry" ] && continue
    rel="${1:+$1/}$(basename "$entry")"
    if [ -d "$entry" ]; then
      case "$rel" in *.framework) continue ;; esac  # a real bundle: codesign signs it as one
      if has_code "$rel"; then
        walk "$rel"
        name="$(basename "$rel")"
        if [[ "$name" == *.* ]]; then
          mv "$entry" "$(dirname "$entry")/${name//./__dot__}"
          ln -s "${name//./__dot__}" "$entry"
        fi
      else
        move_out "$rel"
      fi
    elif ! is_code "$rel"; then
      move_out "$rel"
    fi
  done
}
walk ""

identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
[ -n "$identity" ] || identity=-
# inside out, as codesign wants it: every library, then the frameworks around them, then the programs
sign() { codesign --force --sign "$identity" --options runtime --timestamp=none "$@"; }
while IFS= read -r -d '' lib; do sign "$lib"; done \
  < <(find "$code_root" -type f \( -name "*.so" -o -name "*.dylib" \) -print0)
while IFS= read -r -d '' exe; do
  if file -b "$exe" | grep -q "^Mach-O" && ! file -b "$exe" | grep -q "executable"; then sign "$exe"; fi
done < <(find "$code_root" -type f -path "*.framework/*" -print0)
while IFS= read -r -d '' framework; do
  if [ -n "$(find "$framework" -name Info.plist -print -quit)" ]; then sign "$framework"
  else echo "warning: $framework has no Info.plist, so it is not signed as a bundle"; fi
done \
  < <(find "$code_root" -type d -name "*.framework" -prune -print0)
while IFS= read -r -d '' exe; do
  if file -b "$exe" | grep -q "^Mach-O"; then sign --entitlements "$SRCROOT/App/Engine.entitlements" "$exe"; fi
done < <(find "$code_root" -type f ! -name "*.so" ! -name "*.dylib" ! -path "*.framework/*" -print0)
