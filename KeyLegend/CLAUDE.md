# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

KeyLegend is a macOS menu-bar hotkey cheat-sheet (native Swift/AppKit, SwiftPM executable, macOS 13+). Hold Option (⌥) alone for ~0.35s anywhere on the system and a non-activating overlay panel fades in showing your own hand-written hotkey notes, grouped into categories you define; release Option (or press any other key) and it disappears. No Dock icon or main window (`LSUIElement`), only a menu-bar status item. All UI strings, code comments, and the README are in Traditional Chinese; keep new ones consistent.

There is no in-app editor. The notes are a single plain-text file the user edits in their own text editor; KeyLegend just watches it and hot-reloads on save. This is a deliberate design choice (see `README.md`'s 開發筆記) — a personal cheat sheet is edited a handful of times a year, and a hand-typed file is more valuable (greppable, versionable) than a CRUD GUI.

## Build & run

```bash
./setup-signing.sh   # one-time per machine: creates a self-signed "KeyLegend Local Signing" identity in the login keychain
./build.sh           # swift build -c release → assemble the bundle → codesign → install to /Applications
open /Applications/KeyLegend.app
```

- `build.sh` assembles straight into `/Applications/KeyLegend.app` and leaves no `.app` in the repo, same reasoning as MacCut/AppJump. Override the destination with `INSTALL_DIR=… ./build.sh`.
- Signing matters here more than in MacCut: KeyLegend requires Accessibility (輔助使用) permission for its global modifier-key monitor, and macOS ties that grant to the code signature. Without the local identity, `build.sh` falls back to ad-hoc signing and every rebuild changes the signature, so macOS silently stops delivering events until the user re-authorizes. If a rebuilt app stops reacting to a held Option key, stale/missing Accessibility authorization is the first suspect.
- Detecting the local identity: use `security find-certificate -c "KeyLegend Local Signing"`, not `security find-identity -v` — the latter reports "0 valid identities" for this self-signed cert even though `codesign` works fine with it (same reasoning as MacCut's CLAUDE.md).
- There are no tests and no linter configured.

## Architecture

Single SwiftPM executable target in `Sources/KeyLegend/` (~9 files), no external dependencies beyond `ApplicationServices` (for the Accessibility permission APIs). The end-to-end flow:

1. **`AppDelegate`** wires everything at launch: status item/menu, the Accessibility-permission request/poll dance (mirrors AppJump's `AXPermission` usage almost exactly — see that project's `AppDelegate.swift` if this needs revisiting), and connects `OptionHoldMonitor.onHoldChanged` directly to `OverlayWindowController.show()/hide()`. Also guards against two copies running at once (same pattern as AppJump: a second launch detects the running instance via `NSRunningApplication` and terminates itself).
2. **`OptionHoldMonitor`** is a small state machine built on `NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown])` — deliberately *not* a `CGEventTap` like AppJump's `TriggerTap`. The reason: AppJump needs a tap because it must *consume* (swallow) the chord key it's bound to; KeyLegend never consumes anything, it only observes, so the much simpler global-monitor API is sufficient and avoids replicating AppJump's dedicated-thread/run-loop/timeout-recovery machinery. Both approaches need Accessibility permission on current macOS regardless — that's not something a lighter API sidesteps.
   - State transitions: a `.flagsChanged` event where `modifierFlags.intersection(.deviceIndependentFlagsMask) == .option` (exactly Option, nothing else) arms a 0.35s timer. Any further `.flagsChanged` where that intersection is no longer exactly `.option` (Option released, or another modifier joined — a real shortcut in progress), any `.keyDown`, or an app-switch notification cancels immediately and invalidates the timer. Only if the timer fires while still armed does `onHoldChanged(true)` fire.
   - Preserve this cancel-on-anything-else behavior in any change — it's what stops the overlay from popping up during ⌥Tab, ⌥-click, ⌥-Backspace, etc.
3. **`OverlayWindowController`** owns a single borderless, non-activating `NSPanel` (`.nonactivatingPanel`, `level = .statusBar`, `ignoresMouseEvents = true`, shown via `orderFrontRegardless()`, never `makeKeyAndOrderFront`) so it never steals focus or clicks from the frontmost app. It rebuilds `OverlayColumnsView` from scratch on every `show()` call rather than diffing/caching — content is pure text, cheap to rebuild, and this guarantees a file edit is reflected the very next time Option is held, with no separate invalidation path to keep in sync.
4. **`OverlayColumnsView`** greedily balances groups across 1–4 columns (weighted by entry count) at a fixed column width, and lets height grow to fit — this is why the panel's fitting size is computed from Auto Layout constraints rather than a fixed frame.
5. **`HotkeyStore`** owns the file path (`~/Library/Application Support/KeyLegend/hotkeys.md`), seeds it with a bundled default template on first launch, and exposes the current `[HotkeyGroup]` after parsing. **`HotkeyFileParser`** is a pure, non-throwing `parse(_:) -> [HotkeyGroup]` — malformed lines are silently skipped, never an error state, because a personal notebook shouldn't lose everything over one typo.
6. **`HotkeyFileWatcher`** wraps a `DispatchSourceFileSystemObject` on the file's descriptor and calls `HotkeyStore.reload()` on writes. It's rename-safe: most editors save by writing a temp file and swapping it in, which orphans the original file descriptor, so a `.delete`/`.rename` event triggers a full teardown-and-reopen of the watch (with a short delay so the new file has actually landed) rather than assuming the same descriptor stays valid.

## Relationship to AppJump

KeyLegend and AppJump solve adjacent problems (both react to a held modifier key, both need Accessibility permission) but are architecturally simpler on KeyLegend's side specifically because it never needs to consume events. Don't "simplify" `OptionHoldMonitor` toward `TriggerTap`'s CGEventTap approach — that would be adding complexity to solve a problem KeyLegend doesn't have. Conversely, if a future change needs KeyLegend to *act* on a key (not just observe), that's the point where a CGEventTap becomes necessary and `TriggerTap` is the reference implementation to study.
