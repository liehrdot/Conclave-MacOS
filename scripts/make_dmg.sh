#!/bin/bash
# Packs a built Conclave.app into Conclave.dmg with the usual "drag it to Applications" window.
#   scripts/make_dmg.sh path/to/Conclave.app [out.dmg]
set -euo pipefail
app=$1
out=${2:-Conclave.dmg}
stage=$(mktemp -d)
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
rm -f "$out"
hdiutil create -quiet -volname "Conclave" -srcfolder "$stage" -fs HFS+ -format UDZO "$out"
rm -rf "$stage"
echo "$out: $(du -h "$out" | cut -f1)"
