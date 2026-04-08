<script lang="ts">
  /**
   * Phase 13 Wave 2 — Hook intercept approval overlay.
   *
   * Renders fullscreen above every view (Shell, Chat, Office, Settings…)
   * for approvals that came from the SHELL hook path — i.e. PTY-spawned
   * `claude` running in our private tmux. The SDK path's approval cards
   * stay in ChatView, since the user is already in Chat to send those.
   *
   * Why a separate component:
   *   - Hook approvals are ambient: they fire from a tmux window the
   *     user might not be looking at, possibly from a totally different
   *     device that just curled the relay.
   *   - In remote/hybrid mode, the hook is BLOCKING the shell — we
   *     can't let the user keep ignoring it across views.
   *   - In local mode it's fire-and-forget but we still surface it so
   *     the user can mirror their TUI decision on the phone if they
   *     happen to be on the phone instead.
   */
  import { relay } from '../stores/relay.svelte';
  import type { ApprovalRequest } from '../stores/relay.svelte';
  import { scoreToolDanger, dangerColor, toolIcon } from '../utils/danger';

  // Only show hook-sourced approvals here. SDK ones live in ChatView.
  let hookApprovals = $derived(
    relay.pendingApprovals.filter((a) => a.source === 'hook'),
  );

  let topApproval = $derived<ApprovalRequest | undefined>(hookApprovals[0]);

  let busyId = $state<string | null>(null);

  async function decide(req: ApprovalRequest, decision: 'allow' | 'deny') {
    if (busyId) return;
    busyId = req.id;
    try {
      await relay.respondToApprovalRest(req.id, decision);
    } catch {
      // store re-fetched on error — just show the card again
    } finally {
      busyId = null;
    }
  }

  // ── Per-card derived state (only for the top card) ─────────
  let danger = $derived(
    topApproval ? scoreToolDanger(topApproval.tool, topApproval.details) : 0,
  );
  let borderColor = $derived(dangerColor(danger));
  let icon = $derived(topApproval ? toolIcon(topApproval.tool) : '');
  let toolLower = $derived(topApproval?.tool.toLowerCase() ?? '');

  // Pull tool_input out of the wrapper so the bash/edit/write helpers
  // mirror ApprovalCard.svelte's extraction logic.
  let input = $derived.by(() => {
    if (!topApproval) return {} as Record<string, unknown>;
    const d = topApproval.details;
    if (d?.['tool_input'] && typeof d['tool_input'] === 'object') {
      return d['tool_input'] as Record<string, unknown>;
    }
    return d ?? {};
  });

  let bashCommand = $derived(
    toolLower === 'bash' || toolLower === 'execute' || toolLower === 'shell'
      ? ((input['command'] as string) ?? null)
      : null,
  );

  let editFilePath = $derived(
    toolLower === 'edit' || toolLower === 'replace'
      ? ((input['file_path'] as string) ?? (input['path'] as string) ?? null)
      : null,
  );

  let writeFilePath = $derived(
    toolLower === 'write' || toolLower === 'create'
      ? ((input['file_path'] as string) ?? (input['path'] as string) ?? null)
      : null,
  );

  // Routing badge label / colour
  let routingLabel = $derived.by(() => {
    if (!topApproval?.routingMode) return null;
    if (topApproval.routingMode === 'local') return 'Local · TUI owns';
    if (topApproval.routingMode === 'remote') return 'Remote · phone decides';
    return 'Hybrid · race';
  });
</script>

{#if topApproval}
  <div
    class="overlay"
    role="dialog"
    aria-modal="true"
    aria-labelledby="mt-approval-overlay-title"
  >
    <div class="card" style="--danger: {borderColor}">
      <div class="header">
        <span class="icon" aria-hidden="true">{icon}</span>
        <div class="title-block">
          <div id="mt-approval-overlay-title" class="title">{topApproval.tool}</div>
          {#if routingLabel}
            <div class="routing-badge" data-mode={topApproval.routingMode}>{routingLabel}</div>
          {/if}
        </div>
        {#if hookApprovals.length > 1}
          <span class="queue-count">+{hookApprovals.length - 1} queued</span>
        {/if}
      </div>

      {#if bashCommand}
        <div class="section-label">command</div>
        <pre class="command">{bashCommand}</pre>
      {:else if editFilePath || writeFilePath}
        <div class="section-label">file</div>
        <pre class="command">{editFilePath ?? writeFilePath}</pre>
      {:else}
        <div class="section-label">arguments</div>
        <pre class="command">{topApproval.description || JSON.stringify(input, null, 2)}</pre>
      {/if}

      {#if topApproval.tabId}
        <div class="meta-row">
          <span class="meta-label">tab</span>
          <span class="meta-value">{topApproval.tabId}</span>
        </div>
      {/if}

      <div class="actions">
        <button
          type="button"
          class="action deny"
          disabled={busyId === topApproval.id}
          onclick={() => decide(topApproval, 'deny')}
        >
          {busyId === topApproval.id ? '...' : 'Deny'}
        </button>
        <button
          type="button"
          class="action allow"
          disabled={busyId === topApproval.id}
          onclick={() => decide(topApproval, 'allow')}
        >
          {busyId === topApproval.id ? '...' : 'Allow'}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .overlay {
    position: fixed;
    inset: 0;
    background: rgba(5, 5, 12, 0.78);
    backdrop-filter: blur(8px);
    -webkit-backdrop-filter: blur(8px);
    display: flex;
    align-items: flex-end;
    justify-content: center;
    padding: 16px 16px calc(16px + env(safe-area-inset-bottom));
    z-index: 9999;
    animation: fade-in 140ms ease-out;
  }

  @media (min-width: 768px) {
    .overlay {
      align-items: center;
    }
  }

  @keyframes fade-in {
    from { opacity: 0; }
    to { opacity: 1; }
  }

  .card {
    background: rgba(15, 16, 22, 0.97);
    border: 1px solid var(--danger, rgba(120, 130, 145, 0.5));
    border-radius: 16px;
    padding: 18px 18px 14px;
    width: 100%;
    max-width: 520px;
    color: #e8e8f0;
    box-shadow:
      0 24px 60px rgba(0, 0, 0, 0.6),
      0 0 0 1px rgba(255, 255, 255, 0.04);
    animation: slide-up 160ms ease-out;
  }

  @keyframes slide-up {
    from { transform: translateY(20px); opacity: 0; }
    to { transform: translateY(0); opacity: 1; }
  }

  .header {
    display: flex;
    align-items: center;
    gap: 12px;
    margin-bottom: 14px;
  }

  .icon {
    font-size: 22px;
    line-height: 1;
  }

  .title-block {
    flex: 1;
    min-width: 0;
  }

  .title {
    font-size: 17px;
    font-weight: 600;
    letter-spacing: 0.01em;
  }

  .routing-badge {
    display: inline-block;
    margin-top: 4px;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    padding: 2px 8px;
    border-radius: 999px;
    background: rgba(255, 255, 255, 0.06);
    color: #b3b8c8;
  }

  .routing-badge[data-mode='remote'] {
    background: rgba(80, 160, 255, 0.18);
    color: #a8d0ff;
  }

  .routing-badge[data-mode='hybrid'] {
    background: rgba(180, 120, 255, 0.18);
    color: #d4b3ff;
  }

  .queue-count {
    font-size: 11px;
    color: #888;
    background: rgba(255, 255, 255, 0.04);
    padding: 4px 8px;
    border-radius: 6px;
    white-space: nowrap;
  }

  .section-label {
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.12em;
    color: #6b7080;
    margin-bottom: 6px;
  }

  .command {
    margin: 0 0 12px;
    padding: 10px 12px;
    background: rgba(0, 0, 0, 0.35);
    border-radius: 8px;
    font-family: 'JetBrains Mono', 'SF Mono', Menlo, monospace;
    font-size: 12.5px;
    line-height: 1.5;
    color: #d8d8e6;
    white-space: pre-wrap;
    word-break: break-all;
    max-height: 220px;
    overflow-y: auto;
  }

  .meta-row {
    display: flex;
    gap: 8px;
    font-size: 11px;
    margin-bottom: 12px;
    color: #6b7080;
  }

  .meta-label {
    text-transform: uppercase;
    letter-spacing: 0.1em;
  }

  .meta-value {
    font-family: 'JetBrains Mono', monospace;
    color: #b3b8c8;
  }

  .actions {
    display: flex;
    gap: 10px;
    margin-top: 4px;
  }

  .action {
    flex: 1;
    border: none;
    border-radius: 10px;
    padding: 13px 12px;
    font-size: 15px;
    font-weight: 600;
    cursor: pointer;
    transition: transform 80ms ease, opacity 120ms ease;
    -webkit-tap-highlight-color: transparent;
  }

  .action:active:not(:disabled) {
    transform: scale(0.97);
  }

  .action:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .action.deny {
    background: rgba(239, 68, 68, 0.18);
    color: #ff8a8a;
    border: 1px solid rgba(239, 68, 68, 0.35);
  }

  .action.allow {
    background: rgba(34, 197, 94, 0.22);
    color: #8af0a8;
    border: 1px solid rgba(34, 197, 94, 0.4);
  }
</style>
