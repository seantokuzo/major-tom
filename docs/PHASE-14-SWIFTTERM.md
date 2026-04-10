# Phase 14: "SwiftTerm"

> **Status:** Spec v1 — 2026-04-09
> **Branch:** `phase-14/swiftterm`
> **Predecessor:** Phase 13 "The Shell" (PWA terminal MVP)
> **Successor:** Ground Control macOS app (parallel track)

---

## TL;DR

We are bringing the Phase 13 terminal experience to the native iOS app. Instead of reimplementing xterm.js in Swift (insane), we embed a `WKWebView` that loads a **bundled** terminal page connecting directly to the relay's existing `/shell/:tabId` WebSocket. The native Swift layer handles auth, keyboard management, notifications (including actionable APNs), and all the iOS-specific UX that the PWA can't touch — haptics, Dynamic Island, Watch complications, Siri shortcuts. The existing chat-based Control tab becomes a legacy mode; SwiftTerm becomes the new default.

This is not "load the PWA in a web view." We bundle a **purpose-built** HTML/JS page (~50KB) that contains only xterm.js + our keybar + the WS plumbing. No Svelte, no build framework, no SPA routing. The native app controls everything else.

---

## Why

The PWA terminal works surprisingly well on mobile Safari. But it has hard ceilings:

| PWA Limitation | Native Solution |
|----------------|-----------------|
| Web Push can't fire actions (Allow/Deny) | APNs with actionable categories — tap "Allow" right from the lockscreen |
| No Dynamic Island / Live Activity | Already built (Phase 7) — just needs shell session data |
| No Watch integration | Already built — approval from wrist |
| No Siri shortcuts for approvals | Already built — "Hey Siri, approve" |
| Safari address bar eats screen real estate | WKWebView is full-bleed, no chrome |
| No haptics on key events | UIFeedbackGenerator per keystroke class |
| Clipboard requires user gesture | Native UIPasteboard, no permission prompt |
| Service Worker push unreliable on iOS | APNs is rock-solid, instant delivery |
| Can't background WebSocket | URLSessionWebSocketTask survives background transitions |

The native app already has 90% of the infrastructure: RelayService, AuthService, notifications, Watch connectivity, Live Activity, achievements, office sprites. We're adding one new feature (the terminal) and rewiring one tab.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  iOS App                                                     │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  OfficeView (SpriteKit — unchanged)                    │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  TerminalView (SwiftUI)                                │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │  TerminalTabBar (native SwiftUI)                 │  │  │
│  │  ├──────────────────────────────────────────────────┤  │  │
│  │  │  WKWebView                                       │  │  │
│  │  │  ┌──────────────────────────────────────────┐    │  │  │
│  │  │  │  xterm.js (bundled HTML/JS)              │    │  │  │
│  │  │  │  $ claude                                │    │  │  │
│  │  │  │  > fix the broken test...                │    │  │  │
│  │  │  └──────────────────────────────────────────┘    │  │  │
│  │  ├──────────────────────────────────────────────────┤  │  │
│  │  │  NativeKeybar (SwiftUI)                          │  │  │
│  │  │  [ Esc ][ Tab ][ Ctrl ][ ↑ ][ ↓ ][ ← ][ → ]    │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  ApprovalCard (native SwiftUI overlay, when active)    │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────┬───────────────────────────────────────────────┘
               │ WSS (binary frames) — direct from WKWebView
               │ Path: /shell/:tabId
               ▼
┌─────────────────────────────────────────────────────────────┐
│  Relay Server (unchanged — same /shell/:tabId endpoint)     │
│  tmux -L major-tom → node-pty → claude CLI                  │
└─────────────────────────────────────────────────────────────┘
```

### Key Design Decision: Bundled HTML vs. Loading the PWA

**Option A — Load the PWA URL in WKWebView:** Simplest, but couples the iOS app to the web build pipeline, requires the relay to be reachable at load time (no offline skeleton), and we'd fight the PWA's SPA routing, service worker, viewport lock CSS, and navigation drawer — all stuff we don't want in the native app.

**Option B — Bundle a purpose-built terminal page (chosen):** A single `terminal.html` with inline JS that imports xterm.js from a bundled ES module. ~50KB total. The native layer injects config (relay URL, auth token, tab ID, theme) via `WKUserScript` before the page loads. The page opens a WebSocket to `/shell/:tabId`, attaches xterm, and exposes a `window.MajorTom` bridge object for native↔web communication.

Option B wins because:
1. Works offline (skeleton renders immediately, connects when relay is reachable)
2. No dependency on the web build/deploy pipeline
3. Tiny payload — ships inside the app bundle
4. Full control over the JS environment — no framework overhead
5. Clean native↔web boundary via WKScriptMessageHandler

### Auth Strategy

The relay's `/shell/:tabId` endpoint authenticates via session cookie (primary) or `?token=` query param (dev fallback). For WKWebView:

1. **Cookie injection:** After the native `AuthService` authenticates (Google OAuth or PIN), we have the session JWT. We inject it into the WKWebView's `WKWebsiteDataStore` as an `HTTPCookie` on the relay's domain before loading `terminal.html`.
2. **Fallback:** If cookie injection fails (WKWebView cookie edge cases are real), the native layer passes the token via the `WKUserScript` config object, and the JS connects with `?token=<jwt>` on the WebSocket URL.

No new relay endpoints needed — the existing auth flow handles both paths.

### Native ↔ Web Bridge

Communication between Swift and the terminal page uses `WKScriptMessageHandler` (Swift→JS) and `window.webkit.messageHandlers` (JS→Swift).

**JS → Swift messages** (via `window.webkit.messageHandlers.majorTom.postMessage`):

| Message | Payload | Purpose |
|---------|---------|---------|
| `ready` | `{}` | Terminal JS loaded, ready for config |
| `connected` | `{ tabId }` | WebSocket connected |
| `disconnected` | `{ code, reason }` | WebSocket closed |
| `bell` | `{}` | Terminal bell — trigger haptic |
| `title` | `{ title }` | xterm title change — update tab bar |
| `selection` | `{ text }` | User selected text — copy to clipboard |
| `resize` | `{ cols, rows }` | Terminal dimensions changed |

**Swift → JS messages** (via `webView.evaluateJavaScript`):

| Function | Payload | Purpose |
|----------|---------|---------|
| `MajorTom.connect(config)` | `{ url, token?, tabId, theme }` | Initialize and connect |
| `MajorTom.disconnect()` | — | Graceful close |
| `MajorTom.sendKey(key)` | `{ key, ctrl?, alt?, shift? }` | Inject keystroke from native keybar |
| `MajorTom.resize(cols, rows)` | `{ cols, rows }` | Force resize |
| `MajorTom.setTheme(theme)` | `{ background, foreground, ... }` | Update terminal theme |
| `MajorTom.paste(text)` | `{ text }` | Paste from native clipboard |
| `MajorTom.focus()` | — | Focus terminal + show keyboard |
| `MajorTom.blur()` | — | Blur terminal + hide keyboard |

---

## What Changes on the Relay

Almost nothing. The `/shell/:tabId` WebSocket endpoint already handles everything. Two small additions:

1. **Query-param auth fallback** — The shell route already accepts `?token=` for dev mode. Formalize this: if no session cookie is present, check for a `?token=` query parameter containing a valid JWT. This is the WKWebView escape hatch.

2. **APNs push for approvals** — The relay already fires Web Push notifications for approvals. Add a parallel APNs path: when a push-worthy event fires, also POST to an APNs provider (or use the existing iOS notification relay through the WebSocket → NotificationService path that's already built). Actually — the iOS app's `NotificationService` already handles approval notifications via the WebSocket connection. No relay changes needed for this.

**Total relay diff: ~5 lines** (formalize the existing `?token=` query param parsing in `shell.ts`).

---

## Wave Breakdown

### Wave 1: Basic Terminal Rendering

**Goal:** WKWebView showing a live terminal session, no keyboard interaction yet. Proof-of-concept that xterm.js renders correctly in WKWebView and connects to the relay.

**Files:**

| File | Action | Description |
|------|--------|-------------|
| `ios/MajorTom/Features/Terminal/Resources/terminal.html` | Create | Bundled HTML page with xterm.js, WS plumbing, MajorTom bridge |
| `ios/MajorTom/Features/Terminal/Resources/xterm.min.js` | Create | Vendored xterm.js bundle (v5.x, ~200KB) |
| `ios/MajorTom/Features/Terminal/Resources/xterm.css` | Create | Vendored xterm.js stylesheet |
| `ios/MajorTom/Features/Terminal/Resources/xterm-addon-fit.min.js` | Create | xterm fit addon for auto-sizing |
| `ios/MajorTom/Features/Terminal/Resources/xterm-addon-webgl.min.js` | Create | WebGL renderer for performance |
| `ios/MajorTom/Features/Terminal/Views/TerminalView.swift` | Create | SwiftUI wrapper — hosts WKWebView, manages lifecycle |
| `ios/MajorTom/Features/Terminal/Views/TerminalWebView.swift` | Create | UIViewRepresentable wrapping WKWebView + message handlers |
| `ios/MajorTom/Features/Terminal/ViewModels/TerminalViewModel.swift` | Create | Connection state, tab management, bridge message routing |
| `ios/MajorTom/App/MajorTomApp.swift` | Modify | Add Terminal tab (alongside existing Control tab for now) |

**Acceptance:**
- [x] WKWebView loads bundled terminal.html
- [x] xterm.js renders with correct theme (dark, matching MajorTomTheme)
- [x] WebSocket connects to relay `/shell/:tabId` with cookie auth
- [x] Terminal shows live `claude` output
- [x] Resize on orientation change works

**Xcode Onboarding Note:** This is where you'll build and run for the first time. See the "Xcode Onboarding" section below.

---

### Wave 2: Keyboard & Input

**Goal:** Full text input — both the iOS software keyboard and a native SwiftUI keybar with specialty keys (Esc, Tab, Ctrl, arrows).

**Files:**

| File | Action | Description |
|------|--------|-------------|
| `ios/MajorTom/Features/Terminal/Views/NativeKeybar.swift` | Create | SwiftUI keybar — Esc, Tab, Ctrl, arrows, specialty toggle |
| `ios/MajorTom/Features/Terminal/Views/SpecialtyKeyGrid.swift` | Create | Expanded grid of function keys, Ctrl combos, pipe, etc. |
| `ios/MajorTom/Features/Terminal/Models/KeySpec.swift` | Create | Key definition model (mirrors web `KeySpec`) |
| `ios/MajorTom/Features/Terminal/Views/TerminalView.swift` | Modify | Integrate keybar below WKWebView, handle keyboard avoidance |
| `ios/MajorTom/Features/Terminal/Views/TerminalWebView.swift` | Modify | Forward keybar taps as `MajorTom.sendKey()` calls |

**Acceptance:**
- [x] iOS keyboard appears when tapping terminal
- [x] Keybar shows above iOS keyboard with Esc, Tab, Ctrl, arrows
- [x] Ctrl+C works (sends `\x03`)
- [x] Arrow keys navigate command history
- [x] Tab completion works
- [x] Specialty grid toggle shows extended keys
- [x] Haptic feedback on keybar taps

---

### Wave 3: Multi-Tab Support

**Goal:** Tab bar above the terminal — create, switch, close tmux windows. Mirrors the PWA's ShellTabs component.

**Files:**

| File | Action | Description |
|------|--------|-------------|
| `ios/MajorTom/Features/Terminal/Views/TerminalTabBar.swift` | Create | Horizontal scrolling tab bar with + button |
| `ios/MajorTom/Features/Terminal/Views/CloseTabConfirm.swift` | Create | Confirmation sheet for closing tabs with active processes |
| `ios/MajorTom/Features/Terminal/ViewModels/TerminalViewModel.swift` | Modify | Multi-tab state management, tab CRUD |
| `ios/MajorTom/Features/Terminal/Views/TerminalView.swift` | Modify | Stack tab bar above WKWebView |

**Acceptance:**
- [x] Tab bar shows current tabs with titles
- [x] "+" button creates new tmux window
- [x] Tapping a tab switches to that window
- [x] Close button with confirmation dialog
- [x] Tab titles update from xterm title sequence

---

### Wave 4: Customization & Sync

**Goal:** Keybar customization (reorder, add/remove keys), theme selection, and cross-device preference sync via the relay's `/api/user/preferences` endpoint.

**Files:**

| File | Action | Description |
|------|--------|-------------|
| `ios/MajorTom/Features/Terminal/Views/KeybarCustomizer.swift` | Create | Drag-to-reorder, add/remove keys from library |
| `ios/MajorTom/Features/Terminal/ViewModels/KeybarViewModel.swift` | Create | Keybar layout state, persistence, relay sync |
| `ios/MajorTom/Features/Terminal/Models/TerminalTheme.swift` | Create | Terminal color schemes (Dracula, Solarized, etc.) |
| `ios/MajorTom/Features/Terminal/Views/TerminalSettingsView.swift` | Create | Font size, theme picker, keybar customize entry point |

**Acceptance:**
- [ ] Keybar layout persists across app launches (UserDefaults)
- [ ] Keybar layout syncs to/from relay (matches PWA customization)
- [ ] Theme picker with preview
- [ ] Font size slider (8–32pt)

---

### Wave 5: Polish & Integration

**Goal:** Wire the terminal into all existing iOS features — Live Activity, Dynamic Island, Watch, Siri shortcuts, haptics polish. Make Terminal the default tab. Legacy ChatView becomes accessible from Settings or removed entirely.

**Files:**

| File | Action | Description |
|------|--------|-------------|
| `ios/MajorTom/App/MajorTomApp.swift` | Modify | Terminal becomes default tab, ChatView demoted or removed |
| `ios/MajorTom/Features/LiveActivity/LiveActivityManager.swift` | Modify | Feed terminal session state to Live Activity |
| `ios/MajorTom/Features/Shortcuts/MajorTomShortcuts.swift` | Modify | Add "Open Terminal" shortcut |
| `ios/MajorTom/Features/Terminal/Views/TerminalView.swift` | Modify | Haptic polish, gesture refinement, copy mode |

**Acceptance:**
- [ ] Terminal is default tab on launch
- [ ] Dynamic Island shows active terminal session
- [ ] Watch shows terminal session status
- [ ] "Open Terminal" Siri shortcut works
- [ ] Copy mode: long-press to select, copy to clipboard
- [ ] Paste: long-press keybar area or Ctrl+Shift+V
- [ ] Smooth orientation transitions
- [ ] No memory leaks (WKWebView properly torn down on tab switch)

---

## File Inventory

### New Files (14)

| File | Wave |
|------|------|
| `Features/Terminal/Resources/terminal.html` | 1 |
| `Features/Terminal/Resources/xterm.min.js` | 1 |
| `Features/Terminal/Resources/xterm.css` | 1 |
| `Features/Terminal/Resources/xterm-addon-fit.min.js` | 1 |
| `Features/Terminal/Resources/xterm-addon-webgl.min.js` | 1 |
| `Features/Terminal/Views/TerminalView.swift` | 1 |
| `Features/Terminal/Views/TerminalWebView.swift` | 1 |
| `Features/Terminal/ViewModels/TerminalViewModel.swift` | 1 |
| `Features/Terminal/Views/NativeKeybar.swift` | 2 |
| `Features/Terminal/Views/SpecialtyKeyGrid.swift` | 2 |
| `Features/Terminal/Models/KeySpec.swift` | 2 |
| `Features/Terminal/Views/TerminalTabBar.swift` | 3 |
| `Features/Terminal/Views/CloseTabConfirm.swift` | 3 |
| `Features/Terminal/Views/KeybarCustomizer.swift` | 4 |

### Modified Files (5)

| File | Wave | Change |
|------|------|--------|
| `App/MajorTomApp.swift` | 1, 5 | Add Terminal tab, make it default |
| `project.yml` | 1 | Add Terminal resource bundle target |
| `relay/src/routes/shell.ts` | 1 | Formalize `?token=` query-param auth |
| `Features/LiveActivity/LiveActivityManager.swift` | 5 | Terminal session data |
| `Features/Shortcuts/MajorTomShortcuts.swift` | 5 | Open Terminal shortcut |

---

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| WKWebView keyboard conflicts with native keybar | High | Test early. WKWebView manages its own `inputAccessoryView` — we may need to suppress it and manage focus/blur manually via the bridge. Known pattern in terminal apps (Blink Shell, Terminus). |
| xterm.js WebGL renderer flickers on older devices | Medium | Fall back to canvas renderer on devices without GPU headroom. Detect via `WKWebView` user agent or explicit capability check. |
| WKWebView process termination on memory pressure | Medium | iOS kills the WKWebView render process under memory pressure. Handle `webViewWebContentProcessDidTerminate` — reconnect and show "Terminal reloaded" toast. |
| Cookie injection race (WKWebsiteDataStore async) | Low | Cookie set completes before page load because we control the load trigger. Belt-and-suspenders: also pass token via WKUserScript config. |
| xterm.js touch selection vs. scroll conflict | Medium | PWA already solved this with copy mode toggle. Port the same pattern: default is scroll, long-press activates selection mode. |

---

## Xcode Onboarding Guide

> **For the mobile newbie.** This is your "hold my hand through the Xcode simulator shit" section.

### Prerequisites

1. **Xcode 16+** — Install from the Mac App Store or `xcode-select --install`. It's big (~35GB). Go get a coffee.
2. **XcodeGen** — We use `project.yml` instead of the `.xcodeproj` GUI spaghetti. Install:
   ```bash
   brew install xcodegen
   ```
3. **Simulator runtime** — Xcode ships with the latest iOS simulator. No extra download needed unless you want older versions.

### First Build

```bash
cd ios/

# Generate the Xcode project from project.yml
xcodegen generate

# Open in Xcode
open MajorTom.xcodeproj
```

In Xcode:
1. **Select scheme:** Top-left dropdown → `MajorTom` (not the widget or watch target)
2. **Select simulator:** Next to the scheme → `iPhone 16 Pro` (or any iOS 17+ sim)
3. **Build & Run:** `Cmd+R` (or the ▶ play button)

First build takes a while (compiling Swift, linking frameworks). Subsequent builds are fast.

### The Simulator

- **Keyboard input:** Your Mac keyboard types into the simulator. If the iOS keyboard doesn't appear, go to Simulator menu → I/O → Keyboard → Toggle Software Keyboard (`Cmd+K`).
- **Paste:** `Cmd+V` pastes into the simulator from your Mac clipboard.
- **Rotate:** `Cmd+←` / `Cmd+→` rotates the device.
- **Home screen:** `Cmd+Shift+H` goes to the home screen.
- **Screenshot:** `Cmd+S` saves a screenshot.

### Connecting to the Relay

The simulator's network is your Mac's network. If the relay is running on `localhost:9090`, the simulator reaches it at `localhost:9090`. No special config needed.

1. Start the relay: `cd relay && npm run dev`
2. Run the app in the simulator
3. The pairing screen will appear — enter your relay URL (`http://localhost:9090`)
4. Authenticate (PIN or Google OAuth depending on your config)
5. You should see the terminal tab with a live session

### Common Gotchas

| Problem | Fix |
|---------|-----|
| "No such module 'WidgetKit'" | Build the MajorTom scheme, not MajorTomWidgets |
| Simulator is slow | Enable GPU acceleration: Simulator → Settings → Advanced → Use GPU |
| Can't connect to localhost | Make sure relay is running and not bound to 127.0.0.1 only |
| WKWebView blank white | Check Console.app for WebKit errors. Common: CSP blocking inline scripts |
| Xcode says "signing required" | Set a development team in Signing & Capabilities (free Apple ID works for simulator) |

### Using XcodeBuildMCP

We have the XcodeBuildMCP tool available. Instead of manually clicking Xcode buttons, the agent can:

```
session_set_defaults → project: ios/MajorTom.xcodeproj, scheme: MajorTom
build_run_sim → builds and launches in simulator
screenshot → captures the current state
snapshot_ui → inspects the view hierarchy
```

This is how we'll iterate fast during implementation.

---

## Decided Questions

1. **WebGL vs Canvas renderer** — Start with WebGL (matches PWA), fall back to canvas on `webViewWebContentProcessDidTerminate`.

2. **Kill ChatView** — Terminal replaces it entirely. Same reasoning as Phase 13's "kill the chat window" pivot. Clean break.

3. **Native keybar** — SwiftUI keybar with haptics, not the web-based MobileKeybar. Native keyboard integration is worth the effort.

4. **Font** — SF Mono (ships with iOS, Apple's terminal font).
