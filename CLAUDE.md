# CLAUDE.md

Conclave for Mac: the native macOS app for Conclave (github.com/liehrdot/Conclave), in Swift and SwiftUI. Claude
writes the code, Flo reviews every PR and wants to learn from it: keep PRs small and explain the why in the
description. Code, comments and docs are English; the app's texts follow the Mac's language (English and German,
`App/Localizable.xcstrings`: every new text gets its German translation in the same PR).

Scope (Flo, 2026-11-18): deck building and collection management first. Not on the Mac: the AI upscaler, MPC
Autofill, session tracking (games, opponents, round logs). Plan: https://claude.ai/artifact/UhGuXcZXWCuPiqwjfj9xJ3

## Commands

```bash
swift test --package-path Packages/ConclaveEngine   # engine package tests, also on Linux, offline
scripts/build_engine.sh                             # Conclave's engine at conclave.rev → build/engine (needs uv)
xcodegen generate                                   # Conclave.xcodeproj from project.yml (Mac only)
scripts/make_dmg.sh path/Conclave.app               # Conclave.dmg
```

## Architecture

- Every screen is native; the logic stays in Conclave's Python engine (`desktop/sidecar/backend.spec`, the same
  PyInstaller build the Windows app ships), pinned by commit in `conclave.rev`. Bump it when the app needs a newer
  engine. Conclave's own CI checks the macOS build (`macos-engine.yml`). Don't port engine rules to Swift unless
  there is a reason; one copy of the rules.
- The engine sits in `Contents/Helpers/conclave-backend/` (`scripts/embed_engine.sh`, a post-build step that also
  signs it inside out with `App/Engine.entitlements`); only code stays there: folders and files without code move to `Contents/Resources/conclave-backend/` behind relative symlinks, and folders with code and a dot in their name get `__dot__` (codesign takes a dotted folder for a bundle), like PyInstaller's own .app layout. No App Sandbox
  (Developer ID later, not the App Store); hardened runtime on.
- `Packages/ConclaveEngine/` (no UI, tests on Linux): `EngineAddress` (the `MTGDECK_URL=` line), `EngineFolders`
  (`~/Library/Application Support/MTG Deckbuilder` and `~/Library/Caches/MTG Deckbuilder`, like Conclave's
  `paths.py` on darwin; the start arguments), `EngineRun` (one run: start, output to `logs/backend.log` (previous run
  `backend.1.log`), wait for the address, `stop()` = SIGTERM then SIGKILL), `RestartPolicy` + `EngineSupervisor`
  (back-off 1/2/5/5/5 s, a run of 5 min resets it, then `failed` with the log tail; the twin of the Windows shell's
  `backend.rs`), `EngineClient` (the engine's JSON API with the Bearer token and `Accept-Language`; errors as
  `EngineError`), `DeckSummary`/`DeckGroups` (`GET /api/decks`: pinned, the rest, paused).
- `App/`: `ConclaveApp` (WindowGroup + Settings, the delegate starts the engine and stops it before quitting),
  `EngineModel` (`@Observable`, the one engine; `MTGDECK_BACKEND` points at another engine while developing),
  `RootView` (starting / failed / `DeckBrowser`), `DeckBrowser` (NavigationSplitView: sidebar sections, detail),
  `SettingsView`. `App/AppIcon.icon` = the iPhone app's Icon Composer icon (copy changes from Conclave-iOS).
- CI (`.github/workflows/ci.yml`): package tests on Linux; on `macos-26` with Xcode 26.6 the engine (cached per
  `conclave.rev`), the app signed ad hoc, `codesign --verify`, the bundled engine started from inside the app, and
  `Conclave.dmg` as the artifact `conclave-mac`.

## Rules

- Follow Apple's Human Interface Guidelines for macOS and read the page before deciding (JSON behind every page:
  `https://developer.apple.com/tutorials/data/design/human-interface-guidelines/<page>.json`).
- Every logic change gets a test in a package. No third-party UI libraries.
- No AI features (Flo's rule for Conclave).
