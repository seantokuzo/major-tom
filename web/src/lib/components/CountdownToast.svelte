<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import { toolIcon } from '../utils/danger';
  import type { ApprovalRequest } from '../stores/relay.svelte';

  // Only show countdown toasts when in delay mode
  let isDelayMode = $derived(relay.permissionMode.mode === 'delay');
  let delaySec = $derived(relay.permissionMode.delaySeconds);
  let pendingApprovals = $derived(relay.pendingApprovals);

  // Track countdown state per approval
  interface CountdownEntry {
    requestId: string;
    startedAt: number;
    remaining: number;
  }

  let countdowns = $state<CountdownEntry[]>([]);
  let cancelledIds = $state(new Set<string>());
  let intervalId: ReturnType<typeof setInterval> | undefined;

  // Sync countdowns with pending approvals in delay mode
  $effect(() => {
    if (!isDelayMode) {
      countdowns = [];
      cancelledIds = new Set();
      return;
    }

    // Add new entries for approvals we haven't tracked yet (skip cancelled ones)
    for (const approval of pendingApprovals) {
      if (cancelledIds.has(approval.id)) continue;
      if (!countdowns.find((c) => c.requestId === approval.id)) {
        countdowns.push({
          requestId: approval.id,
          startedAt: Date.now(),
          remaining: delaySec,
        });
      }
    }

    // Remove entries for approvals that are no longer pending
    // Also clean up cancelled IDs for resolved approvals
    const pendingIds = new Set(pendingApprovals.map((a) => a.id));
    countdowns = countdowns.filter((c) => pendingIds.has(c.requestId));
    cancelledIds = new Set([...cancelledIds].filter((id) => pendingIds.has(id)));
  });

  // Tick countdown timers
  $effect(() => {
    if (countdowns.length === 0) {
      if (intervalId) {
        clearInterval(intervalId);
        intervalId = undefined;
      }
      return;
    }

    intervalId = setInterval(() => {
      for (const entry of countdowns) {
        const elapsed = (Date.now() - entry.startedAt) / 1000;
        entry.remaining = Math.max(0, delaySec - elapsed);
      }
      // Force reactivity
      countdowns = [...countdowns];
    }, 100);

    return () => {
      if (intervalId) clearInterval(intervalId);
    };
  });

  function cancelApproval(requestId: string) {
    // Track as cancelled so the $effect doesn't re-add it
    cancelledIds = new Set([...cancelledIds, requestId]);
    // Remove from countdown list — this triggers the full approval card to show
    countdowns = countdowns.filter((c) => c.requestId !== requestId);
    // The approval remains pending — the full ApprovalCard will handle it
  }

  function getApproval(requestId: string): ApprovalRequest | undefined {
    return pendingApprovals.find((a) => a.id === requestId);
  }

  function describeInput(tool: string, details?: Record<string, unknown>): string {
    if (!details) return '';
    const input = (details['tool_input'] && typeof details['tool_input'] === 'object')
      ? details['tool_input'] as Record<string, unknown>
      : details;

    const lower = tool.toLowerCase();
    if (lower === 'bash' || lower === 'execute' || lower === 'shell') {
      const cmd = (input['command'] as string) ?? '';
      return cmd.length > 60 ? cmd.slice(0, 60) + '...' : cmd;
    }
    if (lower === 'edit' || lower === 'write' || lower === 'read') {
      return ((input['file_path'] ?? input['path']) as string)?.split('/').slice(-2).join('/') ?? '';
    }
    return '';
  }

  // Only show toasts for approvals we're counting down (not cancelled ones)
  let visibleToasts = $derived(
    countdowns.filter((c) => pendingApprovals.some((a) => a.id === c.requestId)),
  );

  // Approvals NOT in countdown (cancelled) should show as normal ApprovalCards
  // This is handled by ChatView — it filters pendingApprovals against countdown IDs
  export function getCountdownIds(): Set<string> {
    return new Set(countdowns.map((c) => c.requestId));
  }
</script>

{#if isDelayMode && visibleToasts.length > 0}
  <div class="toast-stack">
    {#each visibleToasts as entry (entry.requestId)}
      {@const approval = getApproval(entry.requestId)}
      {#if approval}
        {@const progress = entry.remaining / delaySec}
        {@const icon = toolIcon(approval.tool)}
        {@const desc = describeInput(approval.tool, approval.details)}
        <div class="toast">
          <div class="toast-progress" style="width: {progress * 100}%"></div>
          <div class="toast-content">
            <span class="toast-icon">{icon}</span>
            <span class="toast-tool">{approval.tool}</span>
            <span class="toast-desc">{desc}</span>
            <span class="toast-time">{Math.ceil(entry.remaining)}s</span>
            <button class="toast-cancel" onclick={() => cancelApproval(entry.requestId)}>
              Cancel
            </button>
          </div>
        </div>
      {/if}
    {/each}
  </div>
{/if}

<style>
  .toast-stack {
    display: flex;
    flex-direction: column;
    gap: 4px;
    padding: var(--sp-xs) var(--sp-md);
    background: rgba(15, 15, 23, 0.8);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
  }

  .toast {
    position: relative;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    overflow: hidden;
  }

  .toast-progress {
    position: absolute;
    top: 0;
    left: 0;
    height: 100%;
    background: rgba(74, 222, 128, 0.06);
    transition: width 0.1s linear;
    pointer-events: none;
  }

  .toast-content {
    position: relative;
    display: flex;
    align-items: center;
    gap: var(--sp-xs);
    padding: 6px var(--sp-sm);
    font-family: var(--font-mono);
    font-size: 0.7rem;
  }

  .toast-icon {
    font-size: 0.8rem;
    flex-shrink: 0;
  }

  .toast-tool {
    color: var(--text-primary);
    font-weight: 600;
    flex-shrink: 0;
  }

  .toast-desc {
    color: var(--text-tertiary);
    flex: 1;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    min-width: 0;
  }

  .toast-time {
    color: var(--allow);
    font-weight: 700;
    font-size: 0.75rem;
    flex-shrink: 0;
    min-width: 24px;
    text-align: right;
  }

  .toast-cancel {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    font-weight: 600;
    color: var(--deny);
    background: rgba(248, 113, 113, 0.1);
    border: 1px solid rgba(248, 113, 113, 0.2);
    border-radius: 3px;
    padding: 2px 8px;
    cursor: pointer;
    flex-shrink: 0;
    transition: all 0.15s;
  }

  .toast-cancel:hover {
    background: rgba(248, 113, 113, 0.2);
  }
</style>
