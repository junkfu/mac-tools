# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

NotchShelf is a macOS menu-bar utility (pure AppKit, no SwiftUI) that lets users stash files by dragging them onto a floating panel under the MacBook notch, then drag them back out to Finder/apps. Stash lives at `~/Library/Application Support/NotchShelf/Stash`. User-facing strings are in Traditional Chinese — keep new UI text consistent with that.

## Build & run

```bash
./build.sh          # swift build -c release → assemble NotchShelf.app → ad-hoc codesign
open NotchShelf.app
```

For a quick compile check: `swift build`. There are no tests or linters. Requires only Xcode Command Line Tools; SwiftPM executable target, macOS 13+, no dependencies.

The app has no `@main`/SwiftUI — `main.swift` manually creates `NSApplication` with `.accessory` activation policy (no Dock icon) so it can be built as a plain SwiftPM executable and wrapped in a bundle by `build.sh`. `Resources/Info.plist` is copied into the bundle by the script; the checked-in `NotchShelf.app/` is a build product.

## Architecture

Single module in `Sources/NotchShelf/`, ~5 classes wired together at launch by `AppDelegate` (also owns the status-bar menu):

- **ShelfStore** — disk + model layer. Owns the stash folder, `items: [URL]` (newest first), and the `removeAfterDrop` UserDefaults setting. All mutations go through `reload()`, which fires `onChange` → the view rebuilds its chips. There is no file watcher: external changes to the stash folder aren't picked up until the next store mutation.
- **NotchWindowController** — owns the `NotchPanel` (a borderless, non-activating `NSPanel` that can never become key/main), computes collapsed/expanded frames from the target screen's notch geometry (`safeAreaInsets` / `auxiliaryTopLeftArea`), and animates between them.
- **ShelfRootView** — panel content view; the drag-*in* target and hover-driven expand/collapse logic. Uses manual frame layout in `layout()` (non-flipped coordinates, offsets measured from the top).
- **ShelfItemView** — one chip per stashed file; the drag-*out* source (`NSDraggingSource` + `NSFilePromiseProviderDelegate`).

### Invariants that are easy to break

**Drag-out is a safe move.** Drag-in always copies (originals untouched). Drag-out uses `NSFilePromiseProvider`, and when `removeAfterDrop` is on, the stash copy is deleted only inside the promise's `writePromiseTo` completion handler — i.e. only after the destination has fully received the bytes. Do not move that deletion into `draggingSession(_:endedAt:)` (that path only handles the Trash `.delete` case); doing so reintroduces a data-loss race on large files.

**Hover expand/collapse is deliberately hardened against flicker.** Several pieces cooperate and each guards a specific failure mode:
- The tracking area is created once with `.inVisibleRect` and never rebuilt — rebuilding it during the frame animation fires spurious enter/exit storms.
- While animating, enter/exit events are ignored (`setAnimating`); on completion `reconcileHoverState()` checks the cursor's real position.
- Collapse is debounced (`scheduleCollapse`, ~0.12s) and re-verifies the cursor position (with a few px tolerance for the top screen edge) before actually collapsing.
- `controller.isDraggingOut` and `isDragInside` both veto collapse; after a drag-out ends the item view must call `scheduleCollapseAfterDragOut()` because no `mouseExited` will fire.

**The panel never takes focus.** `NotchPanel` overrides `canBecomeKey`/`canBecomeMain` to false, and every clickable view overrides `acceptsFirstMouse` to respond without activating. New interactive subviews need the same `acceptsFirstMouse` override or first clicks will be swallowed.

**Within-app drops are disabled** (`sourceOperationMaskFor` returns `[]` for `.withinApplication`) so an item can't be dropped back onto the shelf itself.
