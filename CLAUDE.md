# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

MacCut is a lightweight macOS menu bar screenshot-annotation tool (native Swift/AppKit, SwiftPM executable, macOS 13+). It has no Dock icon or main window (`LSUIElement`), only a ✂️ status item. The result of a capture goes to the clipboard only — nothing is ever saved to disk. All UI strings, code comments, and the README are in Traditional Chinese; keep new ones consistent.

## Build & run

```bash
./setup-signing.sh   # one-time per machine: creates a self-signed "MacCut Local Signing" identity in the login keychain
./build.sh           # swift build -c release → assemble MacCut.app → codesign
open MacCut.app
```

- `swift build` alone compiles but does not produce a runnable `.app`; the app needs the bundle (Info.plist with `LSUIElement`) to behave correctly, so use `./build.sh` for real testing.
- There are no tests and no linter configured.
- Signing matters: without the local identity, `build.sh` falls back to ad-hoc signing, and every rebuild changes the code signature — macOS then re-prompts for the Screen Recording permission (required because the app invokes `screencapture`). If a rebuilt app silently fails to capture, stale Screen Recording authorization is the first suspect: remove the old entry in System Settings → Privacy & Security → Screen Recording and re-authorize.

## Architecture

Single SwiftPM executable target in `Sources/MacCut/` (~900 lines total), links the Carbon framework for global hotkeys. The end-to-end flow:

1. **`AppDelegate`** wires everything: status item menu, hotkey registration, and capture → annotation handoff. It owns the open `AnnotationWindowController`s (multiple annotation windows can be open at once).
2. **`HotKeyManager`** wraps Carbon `RegisterEventHotKey` (global hotkey without Accessibility permission, default ⌘⇧X). **`HotKeyStore`** persists user customization in `UserDefaults` and converts Carbon modifiers ↔ display symbols. Factory default lives in `HotKeyDefaults` (in HotKeyManager.swift); the store overrides it.
3. **`CaptureController`** delegates region selection entirely to the system: it spawns `/usr/sbin/screencapture -i -s -x -c` and reads the image back from the clipboard. Cancellation is detected by comparing `NSPasteboard.changeCount` before/after — if the user pressed Esc, the count didn't change. This delegation is the core design decision (system UI is GPU-composited and lag-free); don't replace it with a custom selection overlay.
4. **`AnnotationWindowController`** builds the floating annotation window (toolbar on top, canvas below), sized to the screenshot and scaled down if it exceeds ~90% of the screen. **`ToolbarView`** is a dumb button strip that reports actions via closures; keyboard shortcuts (⏎ copy, Esc cancel, ⌘Z undo) are implemented as button `keyEquivalent`s, not a key-event monitor.
5. **`AnnotationView`** is the canvas and the performance-sensitive part. Its rendering model: `baseImage` always holds the fully composited current result; `draw(_:)` only draws `baseImage` plus the single in-progress stroke. On `mouseUp` the stroke is "baked" into a new `baseImage` and the previous image is pushed onto a snapshot-based undo stack (depth 30). Copy-to-clipboard just uses `baseImage` directly. Preserve this composite+live-stroke model in any canvas change — it's what keeps drawing lag-free.

### Coordinate spaces in AnnotationView

The canvas may display the image scaled down. Mouse input is in view space; baking happens in image space via `imageSpaceScale` (= image width / view width). Live previews divide line width by the scale so baked and previewed strokes look identical. Everything uses AppKit's bottom-left-origin coordinates throughout (the mosaic patch pipeline deliberately avoids any flipping).

## Tweaking defaults

Documented in README's 開發 section — keep it in sync if these move: default hotkey (`HotKeyDefaults`), toolbar colors (`colors` array in ToolbarView.swift), line width (`baseLineWidth`) and mosaic granularity (`mosaicBlockSize`) in AnnotationView.swift.
