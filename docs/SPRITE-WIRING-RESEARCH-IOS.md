# Sprite-Agent Wiring: iOS Feasibility Research

## Gate 1: Office Manager SwiftUI + SKScene Lifecycle

### What We Found

**Current Architecture:**

- **Entry point:** `OfficeView` is a plain `struct` SwiftUI view at `ios/MajorTom/Features/Office/Views/OfficeView.swift`.
- **Tab wiring:** Directly embedded in the TabView at `MajorTomApp.swift:125`:
  ```swift
  OfficeView(viewModel: officeViewModel, relay: relay)
      .tabItem { Label("Office", systemImage: "building.2") }
      .tag(AppTab.office)
  ```
- **Single OfficeViewModel:** Created as `@State` in `MajorTomApp.swift:6`, passed directly to `OfficeView`. Only one exists.
- **SKScene creation:** The `OfficeScene` is created inline as a `@State` property in `OfficeView` (line 31-36):
  ```swift
  @State private var scene: OfficeScene = {
      let scene = OfficeScene()
      scene.size = CGSize(width: StationLayout.sceneWidth, height: StationLayout.sceneHeight)
      scene.scaleMode = .aspectFill
      return scene
  }()
  ```
- **Scene size:** Each OfficeScene is ~1240x2620 points (the full station layout). It contains: starfield parallax, 8 rooms, furniture, airlocks, grid movement engine, particle effects, camera system, weather engine.
- **Scene lifecycle management:** `onAppear` unpauses the scene + wires engines; `onDisappear` pauses + stops all engines (lines 66-139). The `hasSetup` guard in `OfficeScene.didMove(to:)` prevents re-running setup if SpriteView re-hosts the scene (line 77-86).
- **RelayService wiring:** `officeViewModel` is set on RelayService at `MajorTomApp.swift:29`. All agent events (spawn/working/idle/complete/dismissed) flow through this single ViewModel. There is NO session scoping -- all agent events go to the same OfficeViewModel regardless of session.
- **Session awareness:** `RelayService` tracks `currentSession: RelaySession?` (single) and `sessionList: [SessionMetaInfo]` (multiple). The `sessionList` is populated from `SessionListResponseEvent`. However, agent events have NO session-level routing -- they all hit the single OfficeViewModel.

**SKScene Multi-Instance Analysis:**

1. **Can multiple SKScenes coexist in memory?** Yes. SKScene is a regular reference-type class. Multiple instances can exist simultaneously. Only the one attached to a visible `SpriteView` is actively rendering.
2. **Scene pausing:** `scene.isPaused = true` stops the update/render loop. The node tree stays in memory. This is already used when the Office tab is not visible (line 131-133).
3. **SpriteView lifecycle:** When `SpriteView` leaves the SwiftUI hierarchy, it does NOT automatically destroy the scene. The scene persists as long as something holds a strong reference. However, re-hosting a scene into a new SpriteView will call `didMove(to:)` again (which the `hasSetup` guard already handles).
4. **Memory cost per scene:** Each OfficeScene is heavyweight. It contains: ~8 room modules with furniture nodes, parallax layers, cached window refs, airlock door animations, grid movement engine with pathfinding data, agent sprites (each with texture, label, status dot, mood overlay). Rough estimate: 30-60MB per scene depending on agent count and texture caching. The texture atlas (`CrewSprites`) is shared (loaded once by SpriteKit), so the cost is mainly node tree + engine state.
5. **Warm vs cold tradeoff:** Keeping 2-3 scenes warm (paused in memory) is feasible on modern iPhones (4-8GB RAM). Beyond that, cold-destroying and rebuilding from relay state is the right call. Rebuild cost is dominated by `renderStationHull()`, `renderModuleFurniture()`, `buildMovementGrids()` -- probably 200-500ms.

**Proposed View Hierarchy for Office Manager:**

```
TabView
  -> OfficeTab (replaces current OfficeView in tab bar)
      -> NavigationStack
          -> OfficeManagerView (root -- cards for sessions)
              -> OfficeView(sessionId:) (pushed on card tap)
                  -> SpriteView(scene: scene)
```

- `NavigationStack` is the natural fit -- card tap pushes an Office, back button returns to manager. No sheet (sheets feel wrong for full-screen game views).
- Each `OfficeView` gets its own `OfficeViewModel` scoped to a session. The current single `officeViewModel` at app level becomes a `[String: OfficeViewModel]` dictionary keyed by sessionId.
- `OfficeManagerView` shows cards from `relay.sessionList` and a local `[String: OfficeScene]` cache.
- Scene lifecycle: active (visible in SpriteView), warm (recently viewed, paused, held in the cache dict), cold (not in cache, rebuilt on next visit). A simple LRU with max 2-3 warm slots.

### Feasibility: GREEN

All building blocks exist. The main work is:
1. Replace single `OfficeViewModel` with per-session instances
2. Route agent events by sessionId (requires relay to include sessionId in agent events -- need to verify)
3. Build `OfficeManagerView` card layout
4. Add scene caching with warm/cold lifecycle

### Recommended Approach

1. Create `OfficeManagerView` as a new view that becomes the tab content.
2. Use `NavigationStack` with `navigationDestination(for:)` keyed on session ID.
3. Introduce an `OfficeSceneManager` (or similar) observable class that manages a `[String: (scene: OfficeScene, viewModel: OfficeViewModel)]` dictionary + LRU eviction.
4. Wire `RelayService` to route agent events to the correct per-session `OfficeViewModel` using the event's sessionId (or parentId).
5. When navigating to a cold session, rebuild the scene from relay state (request current agent list from relay).

### Open Questions / Risks

- **Agent events lack sessionId routing:** Currently, `AgentSpawnEvent` has `agentId`, `parentId`, `task`, `role` but no explicit `sessionId`. The relay will need to either (a) include `sessionId` in agent events, or (b) the iOS side tracks which agents belong to which session via the parentId chain. Option (a) is much simpler and should be done in Wave 2.
- **Scene rebuild from relay state:** We need a relay endpoint or message to request "give me all current agents for session X" so cold scenes can rebuild. Currently there's no such message.
- **Memory budget:** 3 warm scenes at ~50MB each = ~150MB. On an iPhone with 4GB RAM, this is acceptable but should be tested. May want to drop to 2 warm max on older devices.
- **InspectorSpriteScene in AgentInspectorView** creates an additional mini SKScene per inspector opening (line 255-339 of AgentInspectorView.swift). These are tiny (80x80) and not a concern.

---

## Gate 2: Local Notification Setup

### What We Found

**Existing Infrastructure (NotificationService.swift):**

- Full `UNUserNotificationCenter` setup already exists at `ios/MajorTom/Features/Notifications/Services/NotificationService.swift`.
- Permission request flow is wired: `requestPermission()` called on pairing (MajorTomApp.swift:64).
- Categories are registered: `APPROVAL_REQUEST` (with Allow/Deny actions) and `SESSION_EVENT`.
- `UNUserNotificationCenterDelegate` is implemented with both `didReceive` (action handling) and `willPresent` (foreground display).
- Local notification posting already works: `postApprovalNotification()`, `postAgentSpawnNotification()`, `postAgentCompleteNotification()`, `postSessionEndNotification()`.
- Deep link handling is wired: `NotificationDeepLink` struct with `majortom://` URL scheme, consumed in `MajorTomApp.swift:72-76`.

**"Cool Beans" Action Button:**

Adding a custom notification category with a "Cool Beans" action button is straightforward:
```swift
let coolBeansAction = UNNotificationAction(
    identifier: "COOL_BEANS_ACTION",
    title: "Cool Beans",
    options: []  // No destructive, no auth required
)
let btwyCategory = UNNotificationCategory(
    identifier: "BTW_RESPONSE",
    actions: [coolBeansAction],
    intentIdentifiers: [],
    options: [.customDismissAction]
)
```
Register alongside existing categories. Handle in the existing `didReceive` delegate method.

**App Foreground/Background Detection:**

- `scenePhase` is already tracked in `MajorTomApp.swift:13` via `@Environment(\.scenePhase)`.
- Currently used only for shortcut action check (line 107-112). Not yet used to gate notification firing.
- Gating logic: check `scenePhase == .background` before posting a `/btw` response notification. Or more robustly, use `UIApplication.shared.applicationState` at the moment of posting (since scenePhase is an environment value, it's trickier to read from a service class).

**WebSocket Background Behavior:**

This is the critical risk area.

- The WebSocket client (`WebSocketClient.swift`) uses `URLSessionWebSocketTask` with `URLSession(configuration: .default)`.
- **iOS suspends apps ~5-10 seconds after backgrounding.** When suspended, the URLSessionWebSocketTask is suspended too -- no messages received.
- **No background modes are configured.** There's no `UIBackgroundModes` in the Info.plist for `voip`, `fetch`, or `remote-notification`.
- **The reconnect logic** (exponential backoff, max 10 attempts) handles disconnects but doesn't address iOS suspension.
- **When the app returns to foreground:** If the WebSocket was not explicitly closed by the server, it may still be connected (TCP keepalive can survive short backgrounds). For longer backgrounds (>30s), the connection is likely dead and reconnect kicks in.

**Notification Delivery When Backgrounded:**

The core problem: if the WebSocket drops when backgrounded, the iOS app cannot receive the `/btw` response at all, so it cannot post a local notification.

Options:
1. **Short background window (~5-10s):** If the response arrives within the iOS suspension grace period, the app is still running and can post the notification. Works for fast responses.
2. **Background URLSession:** Use `URLSession(configuration: .background)` for the WebSocket. However, `URLSessionWebSocketTask` does NOT support background sessions -- only download/upload tasks do.
3. **Silent push notification from relay (APNs):** Relay detects iOS client is not responding, sends a silent push via APNs to wake the app. App wakes for ~30s, reconnects WebSocket, fetches response, posts local notification. This is the most reliable but requires APNs infrastructure (explicitly out of scope per spec).
4. **Background fetch:** Register for background app refresh. iOS calls the app periodically (unpredictable timing, 15min-1hr). App reconnects, checks for pending responses. Too unreliable.
5. **Relay holds response, iOS fetches on foreground return:** The relay queues the response. When the app returns to foreground and reconnects, the relay delivers all pending responses. iOS posts a "you missed this" banner in-app instead of a notification. This is the most practical no-infrastructure option.

### Feasibility: YELLOW

- Adding the notification category + "Cool Beans" action: GREEN, trivial.
- Detecting foreground/background: GREEN, already wired.
- Delivering notification when app is truly backgrounded (>10s): RED without APNs. The WebSocket dies and there's no way to wake the app.
- **Practical compromise:** Local notification works for the brief iOS suspension window (~5-10s). For longer backgrounds, the relay queues responses and delivers them on reconnect. The app shows a "you missed N responses" badge/indicator instead of a push notification.

### Recommended Approach

1. Add a `BTW_RESPONSE` notification category with "Cool Beans" action to the existing `registerCategories()` method.
2. Add a `postBtwResponseNotification(agentId:, response:)` method to NotificationService.
3. Gate posting on `UIApplication.shared.applicationState != .active` (use UIApplication since services can't read scenePhase easily).
4. For the background gap: relay must queue `/btw` responses and deliver them on reconnect. When iOS reconnects and receives a delayed `/btw` response, show it as an in-app banner (not a push notification, since the user is already in the app).
5. Document the limitation: "push notifications for `/btw` responses work reliably only during the ~10s iOS suspension grace period. For longer backgrounds, responses are delivered on next app open." This is honest and matches what local-only notification can achieve.
6. Consider a future phase for APNs if the limitation proves painful.

### Open Questions / Risks

- **BGTaskScheduler:** iOS 17+ has `BGAppRefreshTask`. Could schedule a background task that reconnects and checks for responses. But iOS controls scheduling (could be 15min+) so it's unreliable for timely delivery.
- **WebSocket keepalive in background:** We could request `beginBackgroundTask(withName:)` when a `/btw` message is pending. This gives ~30s of execution time. If the response arrives in that window, we post the notification. Worth implementing.
- **`URLSessionConfiguration.background` for HTTP polling:** Could add a periodic HTTP poll as a background-mode fallback. But this adds complexity and is still unreliable for timing.

---

## Gate 3: Role -> Sprite Mapping Table

### What We Found

**CharacterType Enum (AgentState.swift:17-52):**

14 human types:
| # | Case | Display Name | Visual Theme |
|---|------|-------------|--------------|
| 1 | `alienDiplomat` | Alien Diplomat | Mint green |
| 2 | `backendEngineer` | Backend Engineer | Steel blue |
| 3 | `botanist` | Botanist | Plant green |
| 4 | `bowenYang` | Bowen Yang | Pink/coral (celebrity) |
| 5 | `captain` | Captain | Navy blue |
| 6 | `chef` | Space Chef | White |
| 7 | `claudimusPrime` | Claudimus Prime | Silver/blue (android) |
| 8 | `doctor` | Doctor | White+teal |
| 9 | `dwight` | Dwight | Mustard yellow (The Office) |
| 10 | `frontendDev` | Frontend Dev | Purple/magenta |
| 11 | `kendrick` | Kendrick | Gold (celebrity) |
| 12 | `mechanic` | Mechanic | Orange jumpsuit |
| 13 | `pm` | Project Manager | Yellow/gold |
| 14 | `prince` | Prince | Purple (celebrity) |

7 dog types (never assigned as agent sprites per spec):
`elvis`, `esteban`, `hoku`, `kai`, `senor`, `steve`, `zuckerbot`

**Sprite Assets:**
All 21 character types have full sprite sheets in `Assets.xcassets/CrewSprites.spriteatlas/`. Each has: front, back, left, right, walkLeft1/2, walkRight1/2, plus activity poses (sitting, sleeping, working, exercising for humans; running, sniffing for dogs). Every human type has a complete asset set -- no sharing needed.

**Current Sprite Claiming Code (OfficeViewModel.swift:120-156):**

```swift
func handleAgentSpawn(id: String, role: String, task: String) {
    // ...
    let characterType: CharacterType
    if let claimed = claimRandomSprite() {  // Random from availableSprites pool
        // Consume idle sprite
        characterType = claimed
    } else {
        // Overflow: unrendered human from crew roster
        if let overflow = crewRoster.overflowHuman(excluding: claimedTypes, maxIdleCount: Self.maxIdleHumans) {
            characterType = overflow
        } else {
            // FALLBACK TO DOG (spec says remove this)
            characterType = CharacterType.allCases.filter(\.isDog).randomElement() ?? .elvis
        }
    }
}
```

Key observations:
- `claimRandomSprite()` picks randomly from `availableSprites` set. No role-based selection at all.
- `parentId` is received in `AgentSpawnEvent` (Message.swift:765) but NEVER passed to `handleAgentSpawn()`. The relay call at line 716 only passes `event.agentId, event.role, event.task`.
- Dog fallback at line 139 -- spec says REMOVE this and duplicate humans instead.
- `availableSprites` is rebuilt on `populateIdleSprites()` from the currently-rendered idle sprites.

**Proposed Role -> CharacterType Mapping:**

With 14 humans and 8 canonical roles, we have room. Here's the proposed mapping based on visual/thematic fit:

| Canonical Role | Primary CharacterType | Rationale |
|---|---|---|
| `researcher` | `.botanist` | Research/science vibe, plant-green fits discovery |
| `architect` | `.captain` | Authority, big-picture planning, navy command look |
| `qa` | `.doctor` | Diagnostic, testing, quality -- medical precision |
| `devops` | `.mechanic` | Infrastructure, wrenches, orange jumpsuit = ops |
| `frontend` | `.frontendDev` | Direct name match, purple/magenta = creative |
| `backend` | `.backendEngineer` | Direct name match, steel blue = server-side |
| `lead` | `.pm` | Project management, leadership, gold = authority |
| `engineer` | `.claudimusPrime` | Generic engineer = the android (ship's AI = fitting for Claude agents) |

**Remaining 6 humans for overflow / random:**
- `alienDiplomat` -- good for unrecognized roles (alien = unusual)
- `bowenYang` -- celebrity, fun wildcard
- `chef` -- break-room character
- `dwight` -- comic relief
- `kendrick` -- celebrity, wildcard
- `prince` -- celebrity, wildcard

This gives every canonical role a unique human sprite, with 6 extras for:
1. Random fallback when role is unrecognized
2. Overflow when >8 agents of different roles spawn
3. Idle cosmetic crew

**Clone-Not-Consume Impact:**
The spec's clone-not-consume model means idle sprites are separate from agent sprites. The mapping table only affects which CharacterType gets instantiated for an agent sprite. The idle pool is unaffected. This simplifies things -- we don't need to worry about "stealing" an idle sprite's type.

### Feasibility: GREEN

14 humans, 8 roles, all sprites have full asset sets. The mapping is clean with no gaps.

### Recommended Approach

1. Add a `RoleMapper` utility (or extend `CharacterType`) with:
   ```swift
   static func characterType(forCanonicalRole role: String) -> CharacterType {
       switch role.lowercased() {
       case "researcher": return .botanist
       case "architect": return .captain
       case "qa": return .doctor
       case "devops": return .mechanic
       case "frontend": return .frontendDev
       case "backend": return .backendEngineer
       case "lead": return .pm
       case "engineer": return .claudimusPrime
       default: return randomUnmappedHuman()
       }
   }
   ```
2. Replace `claimRandomSprite()` in `handleAgentSpawn()` with role-based lookup.
3. Add role-stable binding: per-session `[String: CharacterType]` dict that remembers "frontend" -> `.frontendDev` for the session lifetime. First spawn for a role locks it.
4. Remove dog fallback at line 138-139. Replace with human duplication (pick from unmapped humans, then duplicate if all exhausted).
5. Pass `parentId` through from `AgentSpawnEvent` to `handleAgentSpawn()`.

### Open Questions / Risks

- **Relay classifier accuracy:** The 8 canonical roles need to be determined somehow. Options: (a) agent `.md` frontmatter `spriteCategory`, (b) relay regex on task description, (c) iOS-side regex. The spec says relay-side classifier with frontmatter override. This is a relay-side implementation task, not an iOS blocker.
- **Role-stable binding vs session-scoped:** If the same role spawns twice in one session, both get the same CharacterType (by design). Visual differentiation is via desk position. This is fine for typical workflows (1-2 of the same role) but could look odd with 5+ identical sprites. The overflow pool (6 unmapped humans) provides variety for edge cases.
- **Celebrity sprites (bowenYang, kendrick, prince, dwight):** These are fun but potentially confusing as "professional" agent representations. Consider whether they should be in the random overflow pool or excluded from agent assignment entirely (idle-only, like dogs). Recommend: keep them in the random pool -- they add personality.

---

## Summary

| Gate | Feasibility | Blocking Issues |
|------|------------|-----------------|
| Office Manager + SKScene lifecycle | GREEN | Agent events need sessionId routing (relay change) |
| Local notifications | YELLOW | WebSocket dies on background; local-only notification is unreliable beyond ~10s. Practical with queue-and-deliver-on-reconnect fallback. |
| Role -> sprite mapping | GREEN | Clean mapping with surplus sprites. Relay classifier is the only dependency. |

### Cross-Cutting Dependencies

1. **Relay must include `sessionId` in agent events** (spawn, working, idle, complete, dismissed) -- currently missing. Without this, per-session Offices cannot route events correctly.
2. **Relay must provide a "get current agents for session X" query** -- needed for cold scene rebuild.
3. **Relay must queue `/btw` responses for disconnected clients** -- needed for the background notification gap and for reconnect scenarios.
4. **Relay classifier for canonical roles** -- can be deferred to Wave 2 but must be designed with the mapping table above in mind.
