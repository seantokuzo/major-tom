# Future Phase: VSCode Chat Bridge — `@major-tom` Chat Participant

> **Status:** Not yet scheduled. Phase number unassigned. Pick this up whenever we want a VSCode-native chat surface alongside the existing PWA chat. No urgency — slot it whenever it makes sense.
>
> **Origin:** This doc supersedes the original "Companion VSCode Extension" plan in `docs/PLANNING.md:96-143`, which was scoped to bridge into Anthropic's Claude Code VSCode extension. That approach is **not viable** (see "Why we're NOT trying to hijack other chat windows" below). The pivot below is what's actually possible.

---

## TL;DR

Major Tom currently has two surfaces in the PWA:

1. **CLI Tab** — real `tmux`-attached terminal via `xterm.js`, default since Wave 2.5
2. **Chat Tab** — Svelte UI streaming through the Claude Code SDK session (the "SDK chat surface")

This phase **keeps both** and **adds a third surface**: a VSCode extension that registers `@major-tom` as a chat participant in VSCode's native Chat view. Same relay, same protocol, new front-end. Three coexisting surfaces, one backend.

The current PWA chat layer is the **reference implementation** that the VSCode extension ports from — every protocol message the extension needs to handle is one the PWA chat already handles. Do not delete the PWA chat before or during this phase.

---

## The pivot in one sentence

> Stop trying to hook into other people's chat windows; build our own chat experience inside VSCode that lives alongside Copilot in the same Chat view.

---

## Why we're NOT trying to hijack other chat windows

User instinct on this was: "what if the chat window relayed Copilot Chat or Claude Code's VSCode extension chat?" Researched it. Both are sealed black boxes:

### GitHub Copilot Chat — BLOCKED
- Copilot Chat is a closed-source VSCode extension. Microsoft has explicitly stated there is **no extension API to access user messages or interact with Copilot Chat from a third-party extension**: <https://github.com/microsoft/vscode-discussions/discussions/1101>
- Network-level interception (mitmproxy, MITM TLS) violates GitHub's terms of service and breaks on every protocol change. Not a real solution.
- Conclusion: **not hookable.** Period.

### Anthropic's Claude Code VSCode Extension — TECHNICALLY POSSIBLE BUT FRAGILE
- It's a webview-panel extension. VSCode provides **no mechanism for one extension to intercept another extension's webview messages**.
- File-watching its storage directory and parsing the format would work but is unsupported, undocumented, and would break on every Claude Code update.
- Conclusion: **not worth building** — the maintenance cost is unbounded.

### VSCode Chat Participant API — YES (for OUR own participant)
- `vscode.chat.createChatParticipant(id, handler)` lets us register our own participant: <https://code.visualstudio.com/api/extension-guides/ai/chat>
- Constraint: a chat participant can **only see messages where it is mentioned**. We cannot observe Copilot or Claude Code's messages even when sharing the same Chat view.
- This is fine — it means we build a parallel chat experience, not a hijacker.

---

## What the Chat Participant API actually gives us

Real bidirectional chat — this is not a toy or a stub:

| Need | API | Notes |
|---|---|---|
| Receive user prompt | `ChatRequest.prompt` | Plus `ChatContext` for history |
| Stream markdown output | `stream.markdown(text)` | Renders live as bytes arrive — same UX as Copilot's own output |
| Action buttons | `stream.button({ command, title, arguments })` | Click → fires VSCode command (built-in or our own) |
| **Approvals (yes/no)** | `stream.confirmation(title, message, data)` | User clicks → `data` returned to your handler. Replaces our PWA swipe cards (downgrade in UX, gain in native feel). |
| File references | `stream.reference(uri)` | Clickable, opens the file in the editor |
| Progress / spinners | `stream.progress(message)` | "thinking…" indicator |
| Diffs | `vscode.commands.executeCommand('vscode.diff', leftUri, rightUri, title)` | Opens VSCode's **real** diff editor — strictly better than our PWA LCS viewer |
| Followup chips | `provideFollowups` | "did you mean…" suggestions |
| Slash commands | Manifest contribution `chatParticipantCommands` | `/refactor`, `/test`, `/explain` etc. |

**The single non-fixable constraint:** users must type `@major-tom` to invoke (or pin our participant as the workspace's default in their settings). That's the chat-participant contract.

---

## What the PWA chat stays for

Three reasons not to delete the existing PWA chat layer when this phase ships:

1. **It's the only chat surface that works on phones.** The VSCode extension obviously requires desktop VSCode. The PWA chat is the mobile chat experience.
2. **It's the reference implementation.** Every protocol message type (`prompt`, `output`, `tool.start`, `tool.complete`, approval flow) is already wired through the PWA chat. The VSCode extension is essentially a port — having a working version to compare against is invaluable.
3. **No regression cost.** It already works. Two parallel chat surfaces sharing one relay is the goal, not a regression.

---

## MVP scope

A minimum viable VSCode extension that:

1. Registers `@major-tom` chat participant in `package.json` and `extension.ts`
2. Opens a WebSocket to the Major Tom relay (auth flow TBD — see Open Questions below)
3. Forwards user prompts as `{ type: 'prompt', sessionId, text }` (existing protocol — no relay changes)
4. Streams `output` events into `stream.markdown(...)` as they arrive
5. Handles approval requests via `stream.confirmation(...)` → returns user's choice over the same WebSocket as `{ type: 'approval.decision', id, decision }`
6. Disconnects cleanly on extension deactivation; reconnects with backoff on transient drops

That's it. Out of MVP, save for follow-up waves:

- Multi-session switching (one VSCode window = one session for MVP)
- Inline file context (current file, selection, diagnostics) injected into prompts
- Slash commands (`/refactor`, `/test`, `/explain`)
- Sprite/fleet view embedded in chat — sprite UI is too rich for chat-stream primitives, leave it PWA-only
- Approval card visual fidelity — `stream.confirmation` is simpler than the PWA swipe cards. Accept the downgrade.

---

## Proposed file layout

```
vscode-extension/
├── package.json              # extension manifest, declares chatParticipant + activation
├── tsconfig.json
├── esbuild.config.js
├── README.md
└── src/
    ├── extension.ts          # activate/deactivate, register participant
    ├── relay-client.ts       # WebSocket client (port the PWA's RelaySocket pattern)
    ├── chat-participant.ts   # ChatRequest → relay prompt; relay output → ResponseStream
    ├── approval-bridge.ts    # confirmation prompts ↔ relay approval messages
    └── auth.ts               # cookie/token handshake mirroring the PWA
```

The directory does not exist yet. There's a stale scaffold mentioned in `.agents/agents/mt-extension-engineer.md` that was scoped to the old "bridge to Claude Code's extension" plan; it has the right anatomy but the wrong premise. Use it as a starting reference for `package.json` shape and `extension.ts` skeleton, but replace the bridge logic with chat-participant logic.

---

## Relay-side changes

**None required for MVP.** The VSCode extension is just another WebSocket client speaking the existing protocol. Same `prompt`/`output`/`tool.*`/`approval.*` messages. Same auth. Same session model.

If we discover during implementation that the protocol needs an extra field — e.g. a "client type" hint so the relay can adjust streaming chunk sizes for VSCode's stream API — that's a small additive change, not a breaking one.

---

## Reference: PWA chat data flow (what the extension ports from)

| Step | File / Location |
|---|---|
| User types in chat | `web/src/lib/components/ChatView.svelte:51-54` |
| Store sends prompt | `web/src/lib/stores/relay.svelte.ts:130-147` (`sendPrompt`) |
| Wire-format message | `web/src/lib/protocol/messages.ts:9-14` (`{type:'prompt', sessionId, text}`) |
| Relay WS handler | `relay/src/routes/ws.ts:685-710` (case `'prompt'`) |
| Adapter dispatches to SDK | `relay/src/adapters/claude-cli.adapter.ts:132-147` (`sendPrompt`) |
| SDK streams events back | Adapter `consumeStream` → `output` / `tool.start` / `tool.complete` over WS |
| Approval round-trip | `relay/src/routes/ws.ts` approval handler ↔ PWA `ApprovalOverlay.svelte` |

The VSCode extension's `chat-participant.ts` is a port of `ChatView.svelte`'s logic; its `relay-client.ts` is a port of the PWA's `RelaySocket`; its `approval-bridge.ts` is a port of `ApprovalOverlay.svelte`. **Do not delete any of those PWA files when this phase ships** — they remain the mobile chat surface.

---

## Open questions to resolve when scheduling

1. **Auth flow.** PWA auth is a browser session cookie set by `relay/src/routes/auth.ts` (Google OAuth). Options for the extension: (a) launch a browser via `vscode.env.openExternal` to obtain the cookie, then store it in VSCode SecretStorage; (b) use the existing dev-token flow as the canonical auth path; (c) a new dedicated extension-auth path. Pick one at scheduling time — all are workable.
2. **Discovery.** How does the extension find the relay URL? Workspace setting? Auto-detect localhost? `vscode.env.asExternalUri` for tunneled scenarios?
3. **Approval UX downgrade.** PWA chat has rich swipe cards with danger scoring. VSCode chat has yes/no `stream.confirmation`. Acceptable downgrade, or do we want a separate webview panel for approvals (heavier but matches PWA fidelity)?
4. **Session model.** One VSCode window = one session? Session-per-folder? Persistent across windows like the PWA?
5. **Coexistence with Copilot.** When both `@github` and `@major-tom` are active in the same chat panel, are there friction points? (Probably not — they're independent participants — but worth a smoke test.)
6. **Marketplace publishing.** Do we publish to the VSCode marketplace, or just sideload via VSIX for ourselves and a small group of friendlies?

---

## When to schedule

No urgency. Reasonable triggers:

- After Wave 3 (sprite rewire) ships and has been stable in the wild for a while
- When the user wants to use Major Tom from inside VSCode without alt-tabbing to the PWA
- When there's a slow phase to fit it into

**Phase number: TBD.** Slot wherever makes sense. Could be Phase 14, 15, 16, or interleaved with auth-refresh / iOS-shell work. Not blocking anything else.

---

## Sources

- VSCode Chat Participant API: <https://code.visualstudio.com/api/extension-guides/ai/chat>
- VSCode Chat tutorial: <https://code.visualstudio.com/api/extension-guides/ai/chat-tutorial>
- VSCode Language Model API: <https://code.visualstudio.com/api/extension-guides/ai/language-model>
- Microsoft's "no Copilot Chat extension API" acknowledgement: <https://github.com/microsoft/vscode-discussions/discussions/1101>
- Claude Code for VSCode docs: <https://code.claude.com/docs/en/vs-code>
- Copilot Chat extension on the Marketplace: <https://marketplace.visualstudio.com/items?itemName=GitHub.copilot-chat>
- Anthropic Claude Code extension on the Marketplace: <https://marketplace.visualstudio.com/items?itemName=anthropic.claude-code>
- Earlier Major Tom planning context (now superseded): `docs/PLANNING.md:96-143` and `.agents/agents/mt-extension-engineer.md`
