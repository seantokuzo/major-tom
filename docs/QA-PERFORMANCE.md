# QA & Performance Optimization Phase

> **Status:** Ready to execute
> **Predecessor:** Phase 14 Wave 5 + Ground Control Wave 5 (all shipped)
> **Scope:** Both native apps (iOS + macOS) — memory, performance, polish

---

## TL;DR

Both native apps are feature-complete. This phase is about making them **bulletproof** — zero memory leaks, optimized rendering, fast launch, low idle CPU. The user observed Ground Control memory climbing fast (~25MB+). Audit found real issues in both apps.

---

## Ground Control (macOS) — Issues Found

### Critical: LogView materializes all 10k entries (LogView.swift)

`List(logStore.filteredEntries)` creates SwiftUI views for ALL entries, not just visible ones. 10k log entries = 10k `LogRowView` allocations. `prettyJSON` computation via `JSONSerialization` runs on every render, even collapsed rows.

**Fix:** Replace `List` with `LazyVStack` inside `ScrollViewReader`, or use a windowed approach that only renders visible cells. Cache `prettyJSON` results.

### Critical: RelayProcess pipe buffer accumulation (RelayProcess.swift)

`readabilityHandler` reads all buffered data at once. String concatenation with `buffer + text` creates new String objects per read event. Under heavy logging, this allocates continuously with no buffer size limits.

**Fix:** Add maximum buffer size before forcing a flush. Use `String(data:encoding:)` directly. Avoid intermediate concatenations.

### Medium: DashboardView 5-second polling without debounce (DashboardView.swift)

Every poll triggers a full view redraw via `@Observable`. `contentTransition(.numericText())` creates new animation objects on every refresh, even when values haven't changed.

**Fix:** Only update state when values actually change. Use `.equatable()` on cards. Consider increasing poll interval to 10s.

### Low: RelayClient URLSession never invalidated (RelayClient.swift)

URLSession holds background connection pools indefinitely. Never invalidated on cleanup.

**Fix:** Add `deinit { session.invalidateAndCancel() }`.

---

## SwiftTerm (iOS) — Issues Found

### Critical: TerminalViewModel untracked Tasks (TerminalViewModel.swift)

`pushToRelay()` spawns detached `Task { }` instances that are never tracked or cancelled. If the ViewModel deallocates during a network request, tasks continue running. Multiple rapid calls build up an unbounded task queue.

**Fix:** Track tasks in a property, cancel in deinit:
```swift
private var relayTask: Task<Void, Never>?
deinit { relayTask?.cancel() }
```

### Critical: TerminalView orphan Task accumulation (TerminalView.swift)

`updateLiveActivity()` and `showToast()` spawn `Task { }` without tracking. Rapid state changes create orphaned tasks.

**Fix:** Track tasks by purpose (liveActivityTask, toastTask), cancel on view dismissal.

### Medium: WKWebView configuration not fully cleaned (TerminalWebView.swift)

`dismantleUIView` removes message handlers and user scripts but doesn't nil the `WKWebViewConfiguration` reference, which holds strong refs to `WKUserContentController` → Coordinator.

**Fix:** Nil configuration references in dismantleUIView.

### Medium: LiveActivityManager snapshots unbounded (LiveActivityManager.swift)

`snapshots` dictionary accumulates forever. Repeated session start/end cycles grow it without pruning.

**Fix:** Ensure `snapshots.removeValue()` succeeds in `endActivity()`. Add periodic cleanup.

### Low: PhoneWatchConnectivityService message queue (PhoneWatchConnectivityService.swift)

`transferUserInfo()` queues messages without bounds. Rapid terminal state updates fill the watch transfer queue.

**Fix:** Coalesce rapid updates. Deduplicate pending transfers.

### Low: KeybarViewModel sync task leak (KeybarViewModel.swift)

`pushToRelay()` creates detached Tasks without storing references. Rapid calls during customization build up task queue.

**Fix:** Track and cancel in deinit.

---

## Optimization Targets

| Metric | Ground Control | SwiftTerm |
|--------|---------------|-----------|
| Memory (idle) | < 15MB | < 25MB |
| Memory (active, 10k logs) | < 40MB | < 35MB |
| Launch time | < 1s | < 2s |
| Idle CPU | < 1% | < 1% |
| Active CPU (polling) | < 5% | < 3% |

---

## Test Plan

### Ground Control
- [ ] Launch app, start relay, watch memory in Activity Monitor for 5 minutes
- [ ] Generate 10k log entries — memory stays under 40MB
- [ ] Dashboard polling doesn't cause CPU spikes
- [ ] Stop relay — memory drops back down
- [ ] Menu bar icon color changes correctly (green/red/gray)
- [ ] Onboarding wizard works on fresh launch
- [ ] Security panel shows connected devices
- [ ] Log viewer scrolls smoothly at 10k entries

### SwiftTerm
- [ ] Launch app, connect terminal — memory stable
- [ ] Run `claude` session with heavy output — no memory climb
- [ ] Switch tabs 20 times — no leaked WKWebViews
- [ ] Rotate device — smooth resize, no layout glitches
- [ ] Copy mode works (long-press → select → copy)
- [ ] Paste works (long-press keybar)
- [ ] Dynamic Island shows terminal session
- [ ] "Open Terminal" Siri shortcut works
- [ ] Kill app, relaunch — clean state, no stale Live Activities

### Cross-App
- [ ] Start Ground Control → relay starts → connect iOS app → everything works
- [ ] PIN auth flow end-to-end
- [ ] Multiple terminal tabs + heavy logging → both apps stay responsive

---

## Wave Breakdown

### Wave 1: Memory Fixes
Fix all Critical and Medium issues above. Both apps.

### Wave 2: Performance Optimization
- LogView virtualization
- DashboardView debouncing
- xterm.js renderer fallback logic
- Launch time profiling + optimization

### Wave 3: Manual QA
- Full test plan execution
- Edge cases (network drops, relay crash, memory pressure)
- Bug fixes from testing
