#!/bin/bash
# Xcode build step: copies build/engine/conclave-backend into the app's Contents/Helpers and signs it with the
# app's identity (ad hoc without a Developer account). Without a built engine the app still builds, and its window
# says how to build the engine.
set -euo pipefail
engine="$SRCROOT/build/engine/conclave-backend"
dest="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
if [ ! -x "$engine/conclave-backend" ]; then
  echo "warning: no engine in build/engine – run scripts/build_engine.sh"
  exit 0
fi
rm -rf "$dest/conclave-backend"
mkdir -p "$dest"
cp -R "$engine" "$dest/"
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
[ -n "$identity" ] || identity=-
# every library first, then the programs, with the hardened runtime (inside out, as codesign wants it)
sign() { codesign --force --sign "$identity" --options runtime --timestamp=none "$@"; }
while IFS= read -r -d '' lib; do sign "$lib"; done \
  < <(find "$dest/conclave-backend" -type f \( -name "*.so" -o -name "*.dylib" \) -print0)
while IFS= read -r -d '' exe; do
  if file -b "$exe" | grep -q "^Mach-O"; then sign --entitlements "$SRCROOT/App/Engine.entitlements" "$exe"; fi
done < <(find "$dest/conclave-backend" -type f ! -name "*.so" ! -name "*.dylib" -print0)
