# Terminal UX Wave 2 — Touch Text Selection + Copy in xterm.js inside iOS WKWebView

**Research scout deliverable. Design doc, not an implementation.**

- Date: 2026-07-31
- Repo snapshot: `major-tom` @ branch `fix/ios-terminal-paste` (working tree; `terminal.html` + `TerminalWebView.swift` were being edited concurrently by another agent — line numbers below may drift, symbol names will not)
- Scope: how to ship touch selection + copy on the iOS terminal without breaking Wave 1's swipe→arrows and long-press→Paste

---

## 0. Ground truth established (verified, not recalled)

### 0.1 Versions — confirmed by byte comparison, not by memory

The iOS bundle files under `ios/MajorTom/Features/Terminal/Resources/` are **byte-identical copies** of the PWA's `node_modules` (md5-matched):

| Bundled file | Package | Version | Latest on npm (checked 2026-07-31) |
|---|---|---|---|
| `xterm.min.js` | `@xterm/xterm` | **6.0.0** | **6.0.0** |
| `xterm-addon-fit.min.js` | `@xterm/addon-fit` | **0.11.0** | **0.11.0** |
| `xterm-addon-webgl.min.js` | `@xterm/addon-webgl` | **0.19.0** | **0.19.0** |
| `xterm.css` | `@xterm/xterm` (css/xterm.css) | 6.0.0 | — |

md5 evidence: `xterm.min.js` and `web/node_modules/@xterm/xterm/lib/xterm.js` both `d7aaaef27ff18a0e8deff9b29439090e`; the fit/webgl/css files match likewise.

**Filenames are legacy-styled (`xterm-addon-fit.min.js`) but the contents are the new scoped packages.** Don't let the filename fool a future reader into thinking this is `xterm@5.3.0` (the last release of the unscoped `xterm` package).

**Upgrade warranted? No.** The project is already on the newest published `@xterm/*` across the board. Nothing to gain, and v6 is where all the selection API we need lives. (The PWA declares `^6.0.0` / `^0.11.0` / `^0.19.0` in `web/package.json`, so iOS and PWA stay in lockstep if the vendored copies are refreshed from `node_modules`.)

### 0.2 How the page is loaded (matters for clipboard)

`TerminalWebView.loadTerminalPage(_:)` calls `webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceDir)` — so the terminal runs on a **`file://` origin**, not a custom scheme, not a server. Config is injected via a `WKUserScript` at `.atDocumentStart` (`window.__MAJOR_TOM_CONFIG__`). The JS↔Swift bridge is a single `WKScriptMessageHandler` named `majorTom`, and Swift→JS goes through `window.MajorTom.*` via `evaluateJavaScript`.

`webView.scrollView.isScrollEnabled = false`, `bounces = false`, and the page body is `overflow: hidden` with `-webkit-touch-callout: none; -webkit-user-select: none`.

### 0.3 What Wave 1 actually installed

`TerminalWebView.Coordinator.attachTouchGestures(to:)` adds, **to the WKWebView itself** (not the scrollView):

1. `UIPanGestureRecognizer` — `maximumNumberOfTouches = 1`, delegate = Coordinator → `handleTerminalPan(_:)`. Axis-locks on first significant movement, then emits `\e[A`/`\e[B`/`\e[C`/`\e[D` per step (`verticalStep = max(16, fontSize*1.2)`, `horizontalStep = max(10, fontSize*0.65)`).
2. `UILongPressGestureRecognizer` — `minimumPressDuration = 0.5`, delegate = Coordinator → `handleTerminalLongPress(_:)`. Fires `HapticService.impact(.medium)` then `interaction.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: location))`.
3. `UIEditMenuInteraction` (retained on the Coordinator as `editMenuInteraction`). Its delegate returns a **single-item menu**: `Paste`, and returns an *empty* `UIMenu` when `UIPasteboard.general.hasStrings == false`.

`gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)` returns **`true` unconditionally** — our recognizers run alongside everything, including each other and WKWebView's internal recognizers.

Teardown is mirrored in `dismantleUIView` (filters `webView.gestureRecognizers` by `delegate === coordinator`, removes the interaction).

### 0.4 What already exists for selection/copy (and is subtly wrong)

This is the most important pre-existing finding. Three things are already wired, and two of them are bugs:

**(a) `terminal.html` already streams selections to native on every change:**

```js
term.onSelectionChange(function() {
  var sel = term.getSelection();
  if (sel) { postToNative({ type: 'selection', text: sel }); }
});
```

**(b) `TerminalViewModel.handleBridgeMessage` auto-writes them to the system pasteboard:**

```swift
case .selection(let text):
    UIPasteboard.general.string = text
```

So *any* selection change — including every intermediate frame of a future drag, and every programmatic `select()` — silently stomps the user's clipboard. It also posts the **entire selection string** across the JS→Swift bridge on every change; a `selectAll()` over the 5000-line scrollback would push a multi-megabyte string per event. Both need to change in Wave 2 (see §4).

**(c) `TerminalViewModel.setCopyMode(_:)` is vestigial and broken:**

```swift
window.MajorTom._term.options.rightClickSelectsWord = \(enabled);
window.MajorTom._term.select(0, window.MajorTom._term.buffer.active.cursorY, window.MajorTom._term.cols);
```

- `rightClickSelectsWord` is meaningless on touch (no right click, no contextmenu event path being used).
- **`select()`'s `row` is an absolute buffer row index; `buffer.active.cursorY` is viewport-relative (`0…rows-1`).** Verified against `@xterm/xterm@6.0.0` typings (`cursorY`: "ranges between 0 (when the cursor is at baseY) and Terminal.rows - 1") and against `SelectionModel`/`SelectionService.selectLines`, which clamp against `buffer.lines.length`. The correct absolute row is `buffer.active.baseY + buffer.active.cursorY` (or `viewportY + rowInViewport` for a hit-test). Today, as soon as the scrollback is non-empty, "Copy mode ON" highlights and copies **the wrong line**.

The status bar in `TerminalView.swift` exposes this as a toggle button (`copyModeActive`, icon `selection.pin.in.out` / `text.cursor`) with a "COPY MODE" overlay badge. Wave 2 should either fix or replace this whole path — it should not be left as-is alongside a real selection implementation.

---

## 1. xterm.js selection API — as it exists in v6.0.0

All of the following are **public**, present in `@xterm/xterm@6.0.0/typings/xterm.d.ts`, and confirmed against the shipped implementation (`SelectionService.ts` / `SelectionModel.ts`, extracted from the bundled sourcemap).

### 1.1 Accessors

| API | Signature | Notes |
|---|---|---|
| `term.hasSelection()` | `(): boolean` | True only when start ≠ end. |
| `term.getSelection()` | `(): string` | The reason this whole design works — the docs literally say "useful for implementing copy behavior outside of xterm.js". |
| `term.getSelectionPosition()` | `(): IBufferRange \| undefined` | `{ start: {x, y}, end: {x, y} }` where **`y` is an absolute buffer row**. Needed to draw handles. |

### 1.2 Mutators

| API | Signature | Notes |
|---|---|---|
| `term.clearSelection()` | `(): void` | Fires `onSelectionChange`. |
| `term.select(column, row, length)` | `(number, number, number): void` | `row` = **absolute buffer row**. See §1.4 — this *does* span multiple rows. |
| `term.selectAll()` | `(): void` | Whole buffer. |
| `term.selectLines(start, end)` | `(number, number): void` | 0-based **absolute buffer line** indices, inclusive both ends. Clamped internally to `[0, buffer.lines.length-1]`. |

### 1.3 Events

| API | Notes |
|---|---|
| `term.onSelectionChange` | `IEvent<void>` — fires with **no payload**; you pull state yourself. Fires on drag-move, programmatic select, and clear. Already subscribed in `terminal.html`. |
| `term.onScroll` | `IEvent<number>` — new viewport position. Useful to reposition DOM handles when the buffer scrolls under a live selection. |
| `term.buffer.onBufferChange` | `IEvent<IBuffer>` — normal ↔ alternate. Needed for the alt-screen behavior in §5. |

### 1.4 The important detail: `select()` is not limited to one row

`SelectionModel.finalSelectionEnd` computes the end from `selectionStart[0] + selectionStartLength` and **wraps it across `cols`**:

```ts
const startPlusLength = this.selectionStart[0] + this.selectionStartLength;
if (startPlusLength > this._bufferService.cols) {
  if (startPlusLength % cols === 0) return [cols, start[1] + Math.floor(startPlusLength/cols) - 1];
  return [startPlusLength % cols, start[1] + Math.floor(startPlusLength/cols)];
}
return [startPlusLength, start[1]];
```

So an arbitrary reading-order range is expressible through the **public API alone**:

```js
// startRow/endRow are ABSOLUTE buffer rows
const length = (endRow - startRow) * term.cols + (endCol - startCol);
term.select(startCol, startRow, length);
```

This means **we never need `term._core.selectionService`.** No private API, no `allowProposedApi` dependency for selection (`allowProposedApi: true` is already set for other reasons). That's a big deal for review-ability and for surviving future xterm upgrades.

### 1.5 What `getSelection()` gives you for free

`SelectionService.selectionText` already does most of the "clean copy" work the Wave 2 scope asks for:

- Trailing-whitespace trimming per row (`translateBufferLineToString(i, true, …)`).
- **Reflow-aware joining** — rows with `isWrapped === true` are concatenated onto the previous row instead of getting a newline. A wrapped 300-char command comes back as one line, which is exactly what you want when pasting into another shell.
- NBSP → regular space normalization.
- Joined with `\n` (`\r\n` only on `Browser.isWindows`, which is never true here).

**ANSI is already stripped** — the buffer stores decoded cells, not escape bytes, so `getSelection()` can never contain SGR sequences. The Wave 2 scope line "strip ANSI, no space collapse" is therefore already satisfied by the library; don't write a post-processor. The only thing worth adding natively is a trailing-newline trim on the whole string.

### 1.6 Do the `@xterm/addon-*` helpers matter here?

| Addon | Latest | Relevant to Wave 2? |
|---|---|---|
| `@xterm/addon-fit` 0.11.0 | loaded | No (layout only). |
| `@xterm/addon-webgl` 0.19.0 | loaded | **Yes, indirectly.** It *does* render the selection — confirmed `selectionRenderModel` / `selectionBackground` / `selectionForeground` symbols in `addon-webgl.js`. Our theme already sets `selectionBackground: rgba(242,166,65,0.25)`. No work needed; just don't assume selection is invisible under WebGL. |
| `@xterm/addon-canvas` 0.7.0 | not loaded | No. The WebGL addon has a `onContextLoss` handler in `terminal.html` that disposes and falls back to the **DOM renderer** (v6 default), which also renders selection. Fine. |
| **`@xterm/addon-clipboard` 0.2.0** | not loaded | **Not needed for touch selection, but a genuinely attractive adjacent win.** It implements **OSC 52** only — i.e. it lets the *remote program* (vim `set clipboard=unnamed`, tmux, `claude`, `printf '\e]52;c;…\a'`) push text to the client clipboard. Its `IClipboardProvider` is pluggable: a ~15-line provider that base64-decodes and calls `postToNative({type:'copy', text})` would make `y` in vim land on the iOS pasteboard. **File as a Wave 2.5 / follow-up issue, not Wave 2 scope.** |
| `@xterm/addon-search` 0.16.0 | not loaded | No, but note it uses the same `select()`-style highlighting; if search ever lands, the two selection owners will need arbitration. |

**There is no official or third-party touch/mobile selection addon.** `npm view` on `@xterm/addon-touch`, `xterm-addon-touch`, `xterm-touch-select`, `xterm-addon-mobile` all 404. Whatever we build is bespoke.

---

## 2. Touch selection reality on iOS WKWebView

### 2.1 Why nothing works out of the box — three independent reasons

**Reason 1 — xterm.js has literally zero touch handling.** I grepped every selection-relevant source out of the v6.0.0 sourcemap (`SelectionService.ts`, `SelectionModel.ts`, `Mouse.ts`, `MouseService.ts`, `Viewport.ts`, `SelectionRenderModel.ts`): **no `touchstart`, no `touchmove`, no `pointerdown`, no `Gesture`.** Selection is bound exclusively to `mousedown` on `.xterm-screen`, then `mousemove`/`mouseup` on `ownerDocument`:

```ts
this._screenElement.ownerDocument.addEventListener('mousemove', this._mouseMoveListener);
this._screenElement.ownerDocument.addEventListener('mouseup', this._mouseUpListener);
```

**Reason 2 — iOS does not synthesize `mousemove` during a drag.** WebKit fires the synthetic `mouseover/mousemove/mousedown/mouseup/click` burst only for a *tap*. A finger drag produces `touchmove` and (by default) a scroll — never a stream of `mousemove`. So even a "clickable" canvas gets `mousedown` on tap-and-hold-release but never the move stream `SelectionService` needs. This is documented Apple behavior (Safari Web Content Guide → Handling Events; HTML Canvas Guide → Adding Mouse and Touch Controls). Upstream tracks it as xterm.js [#3727](https://github.com/xtermjs/xterm.js/issues/3727) (open, "copy and paste do not work on touch devices", reproduced on canvas/DOM/WebGL alike) and [#5377](https://github.com/xtermjs/xterm.js/issues/5377) (opened 2025-07-20, labeled `help wanted`, no maintainer roadmap, no linked PR).

**Reason 3 — the renderer is a canvas/WebGL surface with `user-select: none`.** `xterm.css` sets `user-select: none; -webkit-user-select: none` on `.xterm`, and `terminal.html` additionally sets `-webkit-touch-callout: none; -webkit-user-select: none` on `html, body`. There is no selectable DOM text under the finger, so the iOS loupe/handles have nothing to grab even if callout were re-enabled. (In the DOM-renderer fallback there *are* per-row spans, but they're still `user-select: none`, and the WebGL path is a single `<canvas>`.)

### 2.2 Bonus finding — the scrollback is currently un-scrollable by touch

v6.0.0 replaced the old native-overflow viewport with VS Code's `SmoothScrollableElement` (`vs/base/browser/ui/scrollbar/scrollableElement.js`), mounted as `.xterm-scrollable-element` inside the `.xterm-viewport` div. Two comments in the vendored source read:

```js
// HACK: xterm.js currnetly requires overflow to allow decorations to escape the container
// element.style.overflow = 'hidden';
```

i.e. **there is no native scrolling container at all** — scrolling is synthetic, driven by `Scrollable` + wheel events + scrollbar-slider `pointerdown` (`abstractScrollbar.js` uses `EventType.POINTER_DOWN` + `GlobalPointerMoveMonitor`). VS Code's `touch.js` (`Gesture`) *is* bundled but is only referenced by `widget.js`'s `ignoreGesture()` — **it is never `addTarget`-ed**, so there is no touch-drag scrolling.

Consequences for this repo right now:

- The `#terminal-container .xterm-viewport { overflow-y: auto; }` rule in `terminal.html` is **dead CSS under v6** — `.xterm-viewport` is just a positioning container; the scroll happens inside `.xterm-scrollable-element`.
- `webView.scrollView.isScrollEnabled = false` removes the last native fallback.
- Therefore the only way a user can currently reach scrollback on the phone is dragging the ~14px synthetic scrollbar slider. Wave 1's pan sends **arrow keys**, which move the shell's readline cursor / history — not the viewport.

**Wave 2 has to own viewport scrolling too**, or drag-selection past the top/bottom edge will be impossible. See §5.

### 2.3 The candidate approaches

#### A. JS touch handlers → buffer cells → `term.select()`, DOM drag handles, native copy

Custom `touchstart`/`touchmove`/`touchend` listeners on `.xterm-screen`, converting client coords to buffer cells and calling the public `select()`.

Coordinate math (all public API, exact — verified against `DomRenderer.ts`, which sets `screenElement.style.width/height` to `cols*cellW` / `rows*cellH`):

```js
const screen = term.element.querySelector('.xterm-screen');
const rect   = screen.getBoundingClientRect();
const cellW  = rect.width  / term.cols;
const cellH  = rect.height / term.rows;
const col    = Math.min(term.cols, Math.max(0, Math.floor((touch.clientX - rect.left) / cellW)));
const vrow   = Math.min(term.rows - 1, Math.max(0, Math.floor((touch.clientY - rect.top) / cellH)));
const absRow = term.buffer.active.viewportY + vrow;   // absolute buffer row
```

`getBoundingClientRect()` on `.xterm-screen` already accounts for the `padding: 2px 4px` this repo puts on `.xterm`, and for the safe-area padding on `#terminal-container`. (xterm's own `getCoordsRelativeToElement` subtracts the *screen* element's padding, which is 0 — same result.)

- **Behavior on iOS:** good, if `preventDefault()` is called on `touchstart`/`touchmove` while in selection mode. Highlight repaints at renderer framerate because `select()` is a synchronous local call — no bridge round-trip per move.
- **What breaks:** everything in §3. The UIKit pan and long-press keep firing underneath and must be gated. `touchcancel` can arrive mid-drag when a UIKit recognizer transitions to `.began` (unconfirmed on device — see §8).
- **Handles:** two absolutely-positioned DOM divs (`position:absolute; z-index:10;` inside `.xterm-screen`'s parent), repositioned from `getSelectionPosition()` on `onSelectionChange` + `onScroll`. Each handle owns its own `touchstart` so a drag on it moves that endpoint instead of starting a new selection. Hit target must be ≥44×44pt with a visual dot smaller than that.
- **Effort:** ~2–3 days including handles, edge auto-scroll, and the gesture gating.

#### B. Native `UIPanGestureRecognizer` in Swift driving JS via `evaluateJavaScript`

Reuse (or add a second) recognizer; on `.changed`, call `MajorTom.selectTo(x, y)` with view coords, and let a tiny JS helper do the cell math + `select()`.

- **Behavior on iOS:** gesture arbitration is entirely in UIKit — no JS/UIKit split-brain, which is the single most attractive property. Latency is an async `evaluateJavaScript` per move; at 60 Hz that's ~60 IPC hops/sec. Workable if coalesced (only send on a changed *cell*, not every point), but the highlight will lag the finger more than approach A.
- **What breaks:** you still need the JS side for cell metrics, so you don't actually escape JS. Handles would be drawn as native `UIView`s over the WKWebView, which means their positions also need a bridge round-trip per scroll/resize — more sync surface, not less.
- **Effort:** ~2 days, but the felt quality ceiling is lower.

#### C. Transparent selectable DOM text layer over the canvas ("let iOS do it")

Overlay a `<pre>` (or per-row `<span>`s) containing the viewport's text at exactly matching metrics, `color: transparent`, `-webkit-user-select: text`, `-webkit-touch-callout: default`, and let iOS's native loupe/handles/callout menu do the selection. Read it back with `window.getSelection()` and map back to buffer cells.

- **Behavior on iOS:** when it works, it's the best-feeling UX on the platform — real loupe, real handles, real magnifier, muscle memory. When it doesn't, it's uncanny-valley garbage.
- **What breaks — a lot:**
  - Metrics must be pixel-perfect against the renderer or the handles land on the wrong glyph. Double-width CJK, emoji (which xterm renders as 2 cells), combining marks, and ligature-ish fallback fonts all desync the two layers.
  - Only the *viewport* is in the DOM. Selecting into scrollback requires continuously rebuilding the layer as the buffer scrolls, while iOS holds a live selection over nodes you're replacing.
  - The system callout menu is what appears, and it is much less controllable than our own `UIEditMenuInteraction` — you get Copy/Look Up/Translate/Share whether you want them or not.
  - You must **re-enable** `-webkit-user-select`/`-webkit-touch-callout`, which resurrects WKWebView's own text-interaction recognizers — which then fight the Wave 1 pan (§3).
  - This is a known-fragile corner of WebKit: [FB/Apple forum thread 797368](https://developer.apple.com/forums/thread/797368) documents a **100%-reproducible WKWebView crash on iOS 26 betas 1–6** triggered by `-webkit-user-select: none` + double-tap-hold-drag, crashing inside `_UIEditMenuContentPresentation`. Fixed in iOS 26 beta 7, but it tells you how much churn lives here.
- **Effort:** ~3–5 days with a real chance of never feeling right. **Not recommended as the primary path.**

#### D. "Granularity ladder" — tap/long-press selection, no drag at all

No touch-drag. Long-press seeds a **word** selection at the press point; the edit menu gains `Select Word` / `Select Line` / `Select All` / `Copy`; repeated taps widen the granularity. All built on `select()` / `selectLines()` / `selectAll()`.

- **Behavior on iOS:** rock solid. Nothing new competes for touches — the long-press recognizer and edit menu already exist and already work.
- **What breaks:** nothing. It just doesn't do arbitrary ranges.
- **Coverage:** honestly high. The dominant real-world use is "copy that error line / that path / that URL / that whole command output block", all of which are word/line/line-range operations.
- **Effort:** ~0.5 day.

#### E. Do nothing in JS; add OSC 52 (`@xterm/addon-clipboard`) only

Only helps when the *remote* program initiates the copy. Doesn't address "I want to copy what's on my screen". Complementary, not a substitute.

---

## 3. Gesture conflict matrix

### 3.1 Who is competing for a touch today

| Layer | Recognizer / behavior | Current state |
|---|---|---|
| Ours (UIKit, on `WKWebView`) | `UIPanGestureRecognizer` → arrow keys | active, `shouldRecognizeSimultaneouslyWith → true` |
| Ours (UIKit, on `WKWebView`) | `UILongPressGestureRecognizer` 0.5s → `presentEditMenu` | active, simultaneous |
| Ours (UIKit) | `UIEditMenuInteraction` | active, Paste-only menu |
| WKWebView internal | scroll pan | **disabled** (`scrollView.isScrollEnabled = false`) |
| WKWebView internal | text-interaction long-press / loupe / callout | **suppressed** by `-webkit-touch-callout: none` + `-webkit-user-select: none` |
| WKWebView internal | double-tap-to-zoom | **suppressed** by `maximum-scale=1.0, user-scalable=no` |
| WKWebView internal | tap → synthetic `click` | active — this is what focuses xterm today |
| Web content (JS) | none | xterm binds no touch events (§2.1) |

### 3.2 Collisions per candidate

| Candidate | Collides with Wave 1 pan | Collides with Wave 1 long-press | Collides with WKWebView internals | Arbitration |
|---|---|---|---|---|
| **A** (JS touch) | **Yes, hard.** A UIKit recognizer you added yourself receives touches through normal hit-testing and is **not** cancelled by JS `preventDefault()`. Both fire → you'd drag a selection *and* spray arrow keys into the shell. | **Yes.** A slow, careful selection drag exceeds 0.5s → the Paste menu pops over the selection mid-drag. | Mild. `preventDefault()` on `touchstart` suppresses the synthetic click, so tap-to-focus stops working *while in selection mode* (desirable). | **Mode flag in both layers.** Swift: `if viewModel.selectionModeActive { return }` at the top of `handleTerminalPan` and `handleTerminalLongPress` (prefer `recognizer.isEnabled = false` — cleaner, cancels an in-flight gesture). JS: only install/act on touch handlers when the mode is on, and `preventDefault()` on `touchstart`+`touchmove`. Add `touch-action: none` on `.xterm-screen`. |
| **B** (native pan) | N/A — same recognizer, mode-switched internally. | Same as A: gate the long-press. | Lowest. No JS touch handlers → synthetic click still works. | One recognizer, `switch mode { case .arrows / .selection }`. |
| **C** (DOM text layer) | **Worst.** Re-enabling `-webkit-user-select: text` resurrects WebKit's own selection pan, which will run *simultaneously* with our pan (delegate returns `true` for everything) → selecting text also emits arrow keys. | Both long-presses fire: ours shows the Paste menu, WebKit's shows the loupe + system callout. Two menus. | High — you're deliberately re-enabling what §0.2 turned off. | Must set `pan.isEnabled = false` **and** `longPress.isEnabled = false` while the overlay is live, and accept the system callout. |
| **D** (tap ladder) | **None.** | Extends it (adds menu items). | None. | Nothing to arbitrate. |

### 3.3 The knobs, and what each actually does

| Knob | Layer | Effect | Gotcha |
|---|---|---|---|
| `UIGestureRecognizerDelegate.shouldRecognizeSimultaneouslyWith` | UIKit | currently returns `true` for *everything* | Wave 2 should stop being unconditional. Returning `false` between our pan and a selection recognizer is a cleaner arbitration than mode flags in some designs. |
| `recognizer.isEnabled = false` | UIKit | cancels in-flight recognition and stops future | Preferred over an early-`return` in the handler: an early return leaves `panAxis`/`lastEmittedTranslation` state mid-drag. If you early-return instead, also reset that state. |
| `recognizer.require(toFail:)` | UIKit | ordering | Useful if you add a selection long-press that must beat the Paste long-press. |
| `preventDefault()` on `touchstart` | Web | kills the synthetic mouse burst + default pan/zoom for that touch | **Does not** stop UIKit recognizers you added to the WKWebView. Must be non-passive (`{passive: false}`) or WebKit ignores it. |
| `preventDefault()` on `touchmove` | Web | stops residual panning | Same passive caveat. |
| `touch-action: none` | CSS | declarative equivalent, fires earlier than JS | Apply to `.xterm-screen` only, not `body`. |
| `-webkit-user-select` | CSS | `none` today (both `body` and `.xterm`) | Only flip to `text` for approach C. Note the iOS 26 beta crash (fixed in beta 7) lived exactly here. |
| `-webkit-touch-callout` | CSS | `none` today on `html, body` | Keeps the system callout out of the way. Leave it. |
| `UIEditMenuInteraction` `targetRectFor` | UIKit | positions the menu against a rect instead of the `sourcePoint` | Wave 2 should implement `editMenuInteraction(_:targetRectFor:)` so the Copy menu anchors to the **selection rect**, not the last touch point. Requires the JS side to report the selection's pixel rect. |

---

## 4. Copy to the iOS pasteboard — recommendation

### 4.1 Does `navigator.clipboard` even exist here?

Partially resolvable from source, and the answer is more nuanced than the usual "file:// isn't secure" folk wisdom.

WebKit's `SecurityOrigin::isPotentiallyTrustworthy()` → `shouldTreatAsPotentiallyTrustworthy(protocol, host)` returns `true` when `LegacySchemeRegistry::shouldTreatURLSchemeAsLocal(protocol)` is true, and `builtinLocalURLSchemes()` in `Source/WebCore/platform/LegacySchemeRegistry.cpp` **contains `"file"_s`**. So on paper a `file://` document **is** a secure context in WebKit, and `navigator.clipboard` should be defined.

But that only clears the *first* gate. WebKit's async clipboard write additionally requires **user activation in the web content process** — per the [WebKit Async Clipboard API post](https://webkit.org/blog/10855/async-clipboard-api/), `writeText` must be called "within user gesture event handlers like `pointerdown` or `pointerup`", and outside that scope the promise rejects immediately. Our copy is triggered from a **native `UIEditMenuInteraction` action** → `webView.evaluateJavaScript(...)`, which carries **no user activation** into the content process (there is no public `evaluateJavaScript(_:inUserGesture:)`). So the very call site we care about is the one most likely to be rejected — silently, with a rejected promise nobody sees.

### 4.2 Verdict: bridge to Swift, set `UIPasteboard.general.string`

**Recommended, unambiguously.** Reasons:

1. **Zero new surface.** The `majorTom` message handler, the `TerminalBridgeMessage.selection(String)` case, and `UIPasteboard.general.string = text` already exist and already work. Wave 2 changes *when* they fire, not *whether* they work.
2. **No user-activation dependency**, no secure-context dependency, no permission prompt, no cross-iOS-version behavioral drift.
3. Native side can pair the write with `HapticService.impact(.light)` + the existing toast, matching the Paste path's feel.
4. It's testable in Swift and reviewable — the "does the clipboard work" question stops being a WebKit trivia question.
5. `document.execCommand('copy')` — the usual `file://` fallback — is a non-starter anyway: it copies the *DOM* selection, and our selection lives in a canvas with `user-select: none`. You'd have to build a hidden textarea + `select()` shim, i.e. reinvent the bridge with more moving parts.

### 4.3 Required changes to the existing bridge (these are bug fixes, not preferences)

**Stop auto-copying on `onSelectionChange`.** Change `terminal.html` to post *state*, not payload:

```js
term.onSelectionChange(function () {
  var pos = term.getSelectionPosition();
  postToNative({ type: 'selection', hasSelection: term.hasSelection(), rect: /* px rect for targetRectFor */ });
});
```

…and add an explicit pull used only when the user taps Copy:

```js
// window.MajorTom
copySelection: function () {
  var sel = term.getSelection();
  if (sel) postToNative({ type: 'copy', text: sel });
}
```

Swift: `case .copy(let text)` → `UIPasteboard.general.string = text` + haptic + toast + `clearSelection()`. Keep `.selection` for menu-enablement state only.

Why this matters beyond correctness: terminal output is **attacker-influenced** content (anything a command prints). Auto-writing it to the system pasteboard on every selection change is both a UX bug (stomps the user's clipboard) and a mild exfiltration hazard that a security specialist will flag in review. It also currently posts the full selected string — potentially megabytes for `selectAll()` — across the bridge on *every* change event, which would fire on every frame of a drag.

---

## 5. Copy mode ↔ scrollback interaction

### 5.1 The constraint

Per §2.2, there is **no touch scrolling in the terminal today**, at all. That's not a Wave 2 regression risk — it's a Wave 2 prerequisite. Dragging a selection to text that's off-screen requires the viewport to move under the finger, and nothing currently moves it.

### 5.2 Edge auto-scroll during a selection drag (required)

While the mode is active and a drag is in progress:

```js
// on each touchmove, plus on a rAF tick while the finger is parked in a hot zone
const HOT = 40; // px
if (y < rect.top + HOT)          term.scrollLines(-1);
else if (y > rect.bottom - HOT)  term.scrollLines(+1);
// then recompute absRow from the NEW term.buffer.active.viewportY and re-select
```

- Run it on a `requestAnimationFrame` loop, not only on `touchmove` — the user parks their finger at the edge and expects continuous scroll. Cancel the loop on `touchend`/`touchcancel`.
- Scroll rate should ramp with how deep into the hot zone the finger is (1 line/frame at the boundary → 3–4 near the edge), otherwise long scrollback crawls.
- **The anchor row is absolute, so it survives scrolling for free.** `SelectionModel.handleTrim` also decrements both endpoints when the scrollback ring evicts lines, and clears the selection if the end scrolls out of the buffer entirely — so a selection anchored 4000 lines back degrades gracefully rather than pointing at garbage.

### 5.3 General (non-selection) touch scrolling — strongly recommended to bundle

Two options, not mutually exclusive:

- **Two-finger pan → `term.scrollLines(±n)`.** A second `UIPanGestureRecognizer` with `minimumNumberOfTouches = 2` (or a JS 2-touch handler). Doesn't collide with Wave 1's pan, which is `maximumNumberOfTouches = 1`. This is the idiomatic terminal-app gesture and matches xterm.js issue [#1007](https://github.com/xtermjs/xterm.js/issues/1007)'s framing.
- **Fatten the synthetic scrollbar** so the existing `pointerdown` slider drag is actually hittable: CSS on `.xterm .xterm-scrollable-element > .scrollbar > .slider` for the visual, and `overviewRuler: { width: N }` in `ITerminalOptions` for the **hit target** (the Viewport maps `overviewRuler?.width` → `verticalScrollbarSize`). Caveat: the typings say `width` "must be set in order to see the overview ruler", so setting it may also switch on decoration rendering in the gutter — **verify visually before shipping** (§8).

### 5.4 The "tmux-mode scrollbar" line in the Wave 2 scope is obsolete

The phase memory (`project_terminal_ux_phase.md`, written 2026-05-23) lists "tmux-mode scrollbar (re-appear when xterm enters alt-screen / copy mode)". **tmux was deleted in the Terminal Reboot (PR #130) — the relay is a plain PTY per tab.** There is no tmux copy mode to detect.

What survives of the intent: alt-screen apps (`claude` TUI, `vim`, `less`, `htop`). But **the alternate buffer has no scrollback by definition** — it is exactly `rows` tall — so a scrollbar there is meaningless and `selectLines()` past the viewport is impossible. The right behavior is the inverse of what the memory says:

```js
term.buffer.onBufferChange(function (buf) {
  // 'alternate' → hide/disable the scrollbar and the scroll gestures;
  // 'normal'    → show them.
});
```

Selection itself should still work in the alt buffer (copying an error out of the `claude` TUI is a top use case) — just clamp the range to the viewport and disable auto-scroll.

Recommend updating the phase doc/memory in the same wave, per the `feedback_phase_spec_flips` rule.

---

## 6. Recommendation + implementation plan

### 6.1 Recommended: **D then A** — ship the ladder first, then add drag

**Wave 2a — "Selection ladder" (approach D).** Long-press already works; extend its menu. Zero gesture risk, ships in a day, and immediately kills the broken `setCopyMode`. This is the de-risking slice: if device QA reveals that our touch assumptions are wrong, 2a still shipped real value.

**Wave 2b — "Drag to select" (approach A).** JS touch handlers + `term.select()` + DOM handles + edge auto-scroll, with the UIKit recognizers gated by a mode flag.

Why A over B for 2b: the selection highlight must track the finger at renderer framerate, and A keeps that loop entirely inside the web content process (`select()` is a synchronous local call). B puts an async IPC hop in the middle of every drag frame and still needs JS for cell metrics — you pay the coordination cost without escaping the coordination.

Why not C: it trades a bounded engineering problem (write the touch handlers) for an unbounded one (keep a shadow DOM text layer pixel-aligned with a canvas across emoji, CJK, wrapping, scrolling, and font fallback), in a corner of WebKit that shipped a 100%-repro crash as recently as iOS 26 beta 6.

### 6.2 Alternatives, with trade-offs and effort

| | Approach | Feel on device | Risk | Effort | Verdict |
|---|---|---|---|---|---|
| 1 | **D → A** (recommended) | Very good; ladder covers most cases immediately, drag covers the rest | Medium — gesture arbitration is the crux | 0.5d + 2–3d | **Recommended** |
| 2 | **A only** | Very good | Medium-high — all eggs in the drag basket, nothing ships if arbitration fights back | 2–3d | Acceptable if you want one PR |
| 3 | **B** (native pan drives JS) | OK; highlight lags the finger | Low-medium; simplest arbitration | ~2d | Fallback if A's JS/UIKit split-brain proves unfixable on device |
| 4 | **D only** | Good, but no arbitrary ranges | Very low | 0.5d | Fine as a permanent answer if 2b keeps slipping |
| 5 | **C** (DOM text layer) | Best when it works, uncanny when it doesn't | **High** | 3–5d, uncertain | Not recommended |

### 6.3 Wave 2a — ordered steps

1. **`TerminalViewModel.swift`** — delete `setCopyMode(_:)`. Add `selectedText: String?` / `hasSelection: Bool` state and a `copySelection()` that calls `MajorTom.copySelection()`. Add `.copy(String)` to `TerminalBridgeMessage` + its `parse`; change `.selection` to carry state, not payload.
2. **`terminal.html`** — replace the `onSelectionChange` payload post with a state post; add `MajorTom.copySelection()`, `MajorTom.selectWordAt(x, y)`, `MajorTom.selectLineAt(y)`, `MajorTom.selectAll()`, `MajorTom.clearSelection()`. Word selection = scan the `IBufferLine` around the hit cell for word boundaries, then `term.select(startCol, absRow, len)`. Line selection = `term.selectLines(absRow, absRow)`.
   - **Use `buffer.active.viewportY + rowInViewport` for the absolute row.** Never `cursorY` (that's the §0.4c bug).
3. **`TerminalWebView.swift`** — expand the `UIEditMenuInteraction` menu: when `hasSelection` → `Copy`, `Select All`, and keep `Paste`; when not → `Select` (word at press point), `Select Line`, `Select All`, `Paste`. Stash the long-press location on the Coordinator so the menu actions know where the press was. Implement `editMenuInteraction(_:targetRectFor:)`.
4. **`TerminalView.swift`** — remove `copyModeActive`, the status-bar toggle, and the "COPY MODE" badge (they're now meaningless), or repurpose the button as "Select All". Keep the toast.

### 6.4 Wave 2b — ordered steps

5. **New file: `ios/MajorTom/Features/Terminal/Resources/terminal-selection.js`** — all touch/selection/handle logic, loaded by `terminal.html` after `xterm.min.js`, exposing `window.MajorTomSelection.{enable, disable, isEnabled}`. Keeping it out of `terminal.html` matters: that file is already ~600 lines and the project's own review rules flag god files. **New resource files must be added to the Xcode target's Copy Bundle Resources phase** — easy to forget, and it fails at runtime, not build time.
6. **`terminal.html`** — `<script src="terminal-selection.js">`; add `.xterm-screen { touch-action: none; }` scoped to selection mode via a body class; delete the dead `.xterm-viewport { overflow-y: auto; }` rule; add handle styles.
7. **`TerminalWebView.swift`** — add `selectionModeActive` to the Coordinator; on enter/exit set `pan.isEnabled` / `longPress.isEnabled` and call `MajorTomSelection.enable()/disable()`. Store the recognizers as Coordinator properties (right now they're only reachable by filtering `webView.gestureRecognizers` on delegate identity — fine for teardown, awkward for toggling).
8. **Edge auto-scroll + handles** in `terminal-selection.js`; reposition handles on `onSelectionChange` and `onScroll`.
9. **Two-finger scroll** — a `minimumNumberOfTouches = 2` pan → `MajorTom.scrollLines(n)`. Small, high value, no conflict with the 1-touch Wave 1 pan.
10. **Alt-buffer gating** via `term.buffer.onBufferChange` (§5.4). Update `docs/STATE.md` + the phase memory to strike the obsolete tmux-scrollbar item.

### 6.5 The risky bits (rank-ordered)

1. **JS↔UIKit split-brain during a drag.** `preventDefault()` does not disarm our own recognizers. If the mode flag desyncs between Swift and JS — e.g. Swift thinks selection mode is off after a tab switch while JS still has handlers installed — you get arrow keys spraying into a live shell while the user drags. **Make Swift the single source of truth**, drive JS from it, and re-assert the mode on every `ready` bridge message and every tab switch.
2. **`touchcancel` mid-drag.** Unconfirmed whether WebKit cancels JS touches when a sibling UIKit recognizer transitions to `.began`. Treat `touchcancel` as "finalize with the last known coords", never as "drop the selection".
3. **`term.reset()` on tab switch wipes the buffer** (`MajorTom.connect` does this when `tabId` changes) — any live selection and its handles must be torn down there or they'll point into a dead buffer.
4. **Handles vs. `fitAddon.fit()`.** Keyboard show/hide and rotation re-fit the terminal, changing `cols`/`rows` and every cell coordinate. Reposition handles on `onResize`, and consider dropping the selection outright on a cols change (the reflow moves the text anyway).
5. **WebGL context loss** disposes the addon and falls back to the DOM renderer; cell metrics are recomputed from `getBoundingClientRect()` so this is survivable, but recompute rather than cache across renderer swaps.
6. **Bridge payload size.** Never post the selection text on a change event (§4.3).

---

## 7. Device QA checklist (Sean's phone)

Run in a normal-buffer shell unless stated. Assume a tab with real scrollback: `ls -la /usr/bin | head -300`.

**Wave 1 non-regression (must all still pass):**
1. Single-finger swipe up/down in the shell → history moves (`\e[A`/`\e[B`), one entry per ~1 line of travel.
2. Single-finger swipe left/right on a long command line → cursor moves per character.
3. Long-press with clipboard text → Paste menu appears at the press point; tapping Paste inserts the text; haptic fires.
4. Long-press with an empty clipboard → no stale/garbage menu.
5. Tap terminal → keyboard raises; keybar keys still work.

**Selection ladder (2a):**
6. Long-press on a word in the middle of a line → that word highlights, menu shows `Copy` + `Select All` + `Paste`.
7. Tap `Copy` → haptic + "Copied" toast; paste into Notes → exactly the word, no leading/trailing spaces.
8. `Select Line` on a line that visually wraps across 3 rows → **one logical line** in the clipboard, no mid-word newlines (this is the `isWrapped` join).
9. `Select All` on a 300-line buffer → clipboard has all of it; app doesn't hang or spike memory.
10. **Scroll the viewport up ~50 lines, then long-press a word.** The highlight must land under the finger, not 50 lines off. *(This is the regression test for the `cursorY` vs `baseY+cursorY` bug in the old `setCopyMode`.)*
11. Copy a line containing a `→`, an emoji, and a box-drawing char → clipboard content matches visually.
12. Copy a line of Claude TUI output containing colors → clipboard has plain text, zero escape sequences.

**Drag selection (2b):**
13. Enter selection mode → drag across 3 lines → highlight tracks the finger with no visible lag; **no characters appear in the shell** (arrow keys are gated).
14. During a selection drag, hold still for >1s → the Paste menu must **not** pop.
15. Drag to the top edge and hold → viewport auto-scrolls up, selection extends continuously; release → selection is stable; scroll back down → the highlight is still on the right text.
16. Drag past the bottom edge → same, downward.
17. Drag a handle to shrink the selection, then the other handle to grow it → both endpoints move independently and the highlight matches.
18. Exit selection mode (or Copy) → swipe-to-arrows works again immediately, first try.
19. Rotate to landscape mid-selection → no crash; handles either follow or the selection clears cleanly.
20. Raise the keyboard with a selection live → `fit()` runs; no orphaned handles floating over the keyboard.
21. Switch tabs with a selection live → no orphan handles, no stale highlight on the new tab.
22. Background the app during a drag, foreground it → no stuck selection mode, no stuck arrow-key emission.

**Scrolling:**
23. Two-finger pan up/down → viewport scrolls smoothly; single-finger still sends arrows.
24. In `claude` / `vim` (alt buffer) → scroll gestures and scrollbar are hidden/disabled; selection still works within the visible screen.

**Clipboard hygiene:**
25. Copy something in Safari → switch to Major Tom → drag a selection but **don't** tap Copy → back to Safari → the original clipboard is intact. *(Regression test for the auto-copy-on-`onSelectionChange` bug.)*

**Stress:**
26. `yes "0123456789abcdefghij" | head -5000` → select-all → copy → paste somewhere. Watch for a hang or a WebContent process kill (`webViewWebContentProcessDidTerminate` → the recovery overlay).

---

## 8. Sources, and what I could NOT confirm

### 8.1 Verified locally (highest confidence — read the actual shipped code)

- Version identity: md5 of `ios/.../Resources/xterm.min.js` vs `web/node_modules/@xterm/xterm/lib/xterm.js`; `web/package-lock.json`; `npm view @xterm/xterm version` → `6.0.0`.
- Selection API surface: `web/node_modules/@xterm/xterm/typings/xterm.d.ts` (v6.0.0) — `hasSelection`, `getSelection`, `getSelectionPosition`, `clearSelection`, `select`, `selectAll`, `selectLines`, `onSelectionChange`, `scrollLines/scrollPages/scrollToTop/scrollToBottom/scrollToLine`, `IBufferRange`, `IBuffer.{cursorY,viewportY,baseY,type,length}`, `onBufferChange`, `IOverviewRulerOptions`.
- Selection semantics: `SelectionService.ts`, `SelectionModel.ts`, `Mouse.ts`, `MouseService.ts`, `Viewport.ts`, `CoreBrowserTerminal.ts`, `DomRenderer.ts`, `scrollableElement.js`, `abstractScrollbar.js`, `widget.js` — all extracted from `xterm.js.map`'s `sourcesContent` (copies live in this session's scratchpad under `xtermsrc/`).
- **Zero touch/pointer handling in xterm's selection path**; `Gesture` bundled but never `addTarget`-ed.
- WebKit `file://` trustworthiness: `Source/WebCore/page/SecurityOrigin.cpp` (`shouldTreatAsPotentiallyTrustworthy` → `shouldTreatURLSchemeAsLocal`) + `Source/WebCore/platform/LegacySchemeRegistry.cpp` (`builtinLocalURLSchemes()` contains `"file"_s`), both from `raw.githubusercontent.com/WebKit/WebKit/main`.
- `@xterm/addon-clipboard` scope: its README + `typings/addon-clipboard.d.ts` on GitHub master — OSC 52 only, pluggable `IClipboardProvider`.
- No touch addon exists: `npm view` 404s on the four plausible names.

### 8.2 Documentation / community (medium-high confidence)

- [xterm.js API — Terminal](https://xtermjs.org/docs/api/terminal/classes/terminal) (via Context7 `/websites/xtermjs`) — `getSelection` is explicitly documented as the hook "for implementing copy behavior outside of xterm.js".
- [xterm.js #3727 — Copy and paste do not work on touch devices](https://github.com/xtermjs/xterm.js/issues/3727) — open; reproduced across canvas/DOM/WebGL; no workaround published.
- [xterm.js #5377 — Limited touch support on mobile devices](https://github.com/xtermjs/xterm.js/issues/5377) — opened 2025-07-20, `help wanted`, no maintainer roadmap, no linked PR.
- [xterm.js #1007 — Touch scrolling should send arrow keys](https://github.com/xtermjs/xterm.js/issues/1007) — the prior art Wave 1 effectively implemented.
- [Safari Web Content Guide — Handling Events](https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/SafariWebContent/HandlingEvents/HandlingEvents.html) and [HTML Canvas Guide — Adding Mouse and Touch Controls to Canvas](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/HTML-canvas-guide/AddingMouseandTouchControlstoCanvas/AddingMouseandTouchControlstoCanvas.html) — synthetic mouse events fire only for taps; use `preventDefault()` on `touchstart` to stop the default pan.
- [WebKit — Async Clipboard API](https://webkit.org/blog/10855/async-clipboard-api/) — user-gesture requirement, secure-context requirement, immediate promise rejection outside a gesture.
- [Apple — UIEditMenuInteraction](https://developer.apple.com/documentation/uikit/uieditmenuinteraction) and [`editMenuInteraction(_:targetRectFor:)`](https://developer.apple.com/documentation/uikit/uieditmenuinteractiondelegate/editmenuinteraction(_:targetrectfor:)); [WWDC22 — Adopt desktop-class editing interactions](https://developer.apple.com/videos/play/wwdc2022/10071/).
- [Apple Developer Forums 797368 — WKWebView crash on iOS 26 Beta with `-webkit-user-select: none`](https://developer.apple.com/forums/thread/797368) — 100% repro on betas 1–6, fixed in beta 7; crashes inside `_UIEditMenuContentPresentation`.
- [MDN — Secure Contexts](https://developer.mozilla.org/en-US/docs/Web/Security/Defenses/Secure_Contexts), [MDN — Clipboard.writeText](https://developer.mozilla.org/en-US/docs/Web/API/Clipboard/writeText).

### 8.3 NOT confirmed — needs on-device experimentation before Wave 2 is locked

I am flagging these explicitly rather than asserting them. Each is cheap to settle with a 30-minute Safari-Web-Inspector session against a DEBUG build (`webView.isInspectable = true` is already set under `#if DEBUG`).

1. **Does `navigator.clipboard` actually exist under `file://` in WKWebView on Sean's iOS version, and does `writeText` succeed from an `evaluateJavaScript` call?** The WebKit source says the origin is potentially-trustworthy, but the user-activation gate is the real question and I could not find an authoritative statement about `evaluateJavaScript`'s activation status. **This does not block the recommendation** (we're using the native bridge either way) — but it's worth logging `window.isSecureContext` and `typeof navigator.clipboard` once, for the record.
2. **Does WebKit fire `touchcancel` in JS when a sibling UIKit `UIPanGestureRecognizer` added to the WKWebView transitions to `.began`?** I could not find a definitive answer. This is the #1 correctness risk for approach A. Test: install a logging `touchstart/touchmove/touchcancel/touchend` handler, drag, and watch the console while the Wave 1 pan is active.
3. **Does JS `preventDefault()` on `touchstart` suppress our own UIKit recognizers?** My strong expectation is **no** (they're outside WebKit's gesture arbitration), which is why §3 recommends explicit `isEnabled` gating rather than relying on `preventDefault`. Worth confirming, because if the answer is "yes" the whole arbitration story simplifies.
4. **Whether `overviewRuler: { width: N }` widens the scrollbar hit target without also turning on visible gutter decorations.** The Viewport maps it to `verticalScrollbarSize`, but the typings imply it also gates overview-ruler rendering. Visual check only.
5. **Whether the WebGL renderer is actually active on Sean's device** (the `try/catch` silently falls back). Affects nothing about selection correctness — both renderers paint it — but affects perceived drag smoothness. Log which renderer won.
6. **Whether the DOM handles need to live inside `.xterm-screen` or as siblings**, given the WebGL canvas stacking and `xterm.css`'s `.xterm-screen canvas { position: absolute }`. Trivial to settle, but it determines whether handle coordinates are screen-relative or container-relative.
7. **Whether the synthetic scrollbar slider is currently draggable by touch at all** (it uses `pointerdown`, which should work for touch, but with `webView.scrollView.isScrollEnabled = false` and the page `overflow: hidden` I could not verify end-to-end). This changes how urgent the two-finger-scroll item in §5.3 is.
8. **Wave 1 device QA is still unconfirmed** (per `docs/STATE.md` and `project_terminal_lan_connect_handoff`). Wave 2b's gesture arbitration is designed against Wave 1's *code*, not against observed Wave 1 *behavior*. If Wave 1's pan turns out to feel wrong on device and gets retuned, revisit §3.
