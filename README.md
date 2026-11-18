# Conclave for Mac

The native macOS app for [Conclave](https://github.com/liehrdot/Conclave), the Commander deckbuilder: build decks and
manage your collection on the Mac, synced with the Windows app and the phone.

Every screen is SwiftUI (with AppKit where it helps). Underneath runs the same engine the Windows app ships (Conclave's
Python backend, built for Apple silicon), so deck checks, brackets, prices and sync work exactly like on the PC. The
app follows the Mac's language: English and German.

## Install from the DMG

Every CI run keeps `Conclave.dmg` as its artifact (Actions › the run › Artifacts › `conclave-mac`).

1. Open the DMG and drag Conclave into Applications.
2. Open Conclave. The app isn't signed by Apple yet (no Developer account), so macOS says it can't check it: click
   **Done**.
3. Open **System Settings › Privacy & Security**, scroll down and click **Open Anyway** next to Conclave.

macOS asks once per new version. A copy you build yourself in Xcode opens without asking.

## Build it yourself

```bash
brew install uv xcodegen
scripts/build_engine.sh      # the engine from the Conclave commit in conclave.rev → build/engine
xcodegen generate            # Conclave.xcodeproj
open Conclave.xcodeproj      # pick "My Mac", Run
```

Your decks, collection and sync state live in `~/Library/Application Support/MTG Deckbuilder`.
