<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import type { CIRunEntry } from '../protocol/messages';

  let expandedRun = $state<number | null>(null);
  let branchFilterInput = $state('');
  let appliedBranchFilter = $state('');
  let autoRefresh = $state(true);

  function close() {
    relay.ciPanelOpen = false;
    expandedRun = null;
    branchFilterInput = '';
    appliedBranchFilter = '';
    relay.ciError = null;
    autoRefresh = true;
  }

  // Fetch data when panel opens
  $effect(() => {
    if (!relay.ciPanelOpen || !relay.sessionId) return;
    relay.requestCIRuns(appliedBranchFilter || undefined);
  });

  // Escape key close
  $effect(() => {
    if (!relay.ciPanelOpen) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') close();
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  // Auto-refresh every 30s when enabled and panel open
  $effect(() => {
    if (!relay.ciPanelOpen || !autoRefresh || !relay.sessionId) return;
    const filter = appliedBranchFilter;
    const interval = setInterval(() => {
      relay.requestCIRuns(filter || undefined);
    }, 30_000);
    return () => clearInterval(interval);
  });

  function refresh() {
    relay.requestCIRuns(appliedBranchFilter || undefined);
  }

  function applyBranchFilter() {
    expandedRun = null;
    appliedBranchFilter = branchFilterInput;
    relay.requestCIRuns(appliedBranchFilter || undefined);
  }

  function selectRun(run: CIRunEntry) {
    if (expandedRun === run.id) {
      expandedRun = null;
      return;
    }
    expandedRun = run.id;
    relay.requestCIRunDetail(run.id);
  }

  function statusIcon(status: string, conclusion: string): string {
    if (conclusion === 'success') return '\u2713';
    if (conclusion === 'failure') return '\u2717';
    if (status === 'in_progress') return '\u25CB';
    return '\u25C7';
  }

  function statusClass(status: string, conclusion: string): string {
    if (conclusion === 'success') return 'status-success';
    if (conclusion === 'failure') return 'status-failure';
    if (status === 'in_progress') return 'status-in-progress';
    return 'status-queued';
  }

  function conclusionLabel(conclusion: string): string {
    if (!conclusion) return '';
    return conclusion.charAt(0).toUpperCase() + conclusion.slice(1).replace(/_/g, ' ');
  }

  function timeAgo(dateStr: string): string {
    const diff = Date.now() - new Date(dateStr).getTime();
    const mins = Math.floor(diff / 60000);
    if (mins < 1) return 'just now';
    if (mins < 60) return `${mins}m ago`;
    const hrs = Math.floor(mins / 60);
    if (hrs < 24) return `${hrs}h ago`;
    const days = Math.floor(hrs / 24);
    if (days < 30) return `${days}d ago`;
    return new Date(dateStr).toLocaleDateString();
  }

  function formatDuration(startedAt: string | null, completedAt: string | null): string {
    if (!startedAt || !completedAt) return '';
    const ms = new Date(completedAt).getTime() - new Date(startedAt).getTime();
    if (ms < 1000) return '<1s';
    const secs = Math.floor(ms / 1000);
    if (secs < 60) return `${secs}s`;
    const mins = Math.floor(secs / 60);
    const remSecs = secs % 60;
    return `${mins}m ${remSecs}s`;
  }

  function eventLabel(event: string): string {
    return event.replace(/_/g, ' ');
  }
</script>

{#if relay.ciPanelOpen}
  <div class="panel-backdrop" role="button" tabindex="0" aria-label="Close CI panel" onclick={close} onkeydown={(e) => { if (e.key === 'Escape' || e.key === 'Enter' || e.key === ' ') { e.preventDefault(); close(); } }}>
    <div class="panel" role="dialog" aria-label="CI Dashboard panel" onclick={(e) => e.stopPropagation()} onkeydown={() => {}}>
      <div class="panel-header">
        <span class="panel-title">
          <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor" class="title-icon">
            <path d="M8 0a8 8 0 110 16A8 8 0 018 0zm0 1.5a6.5 6.5 0 100 13 6.5 6.5 0 000-13zM6.5 5a1 1 0 011.04.037l4 2.75a1 1 0 010 1.652l-4 2.75A1 1 0 016 11.25v-5.5A1 1 0 016.5 5z"/>
          </svg>
          CI Runs
        </span>
        <div class="header-actions">
          <button
            class="auto-refresh-btn"
            class:active={autoRefresh}
            onclick={() => (autoRefresh = !autoRefresh)}
            title={autoRefresh ? 'Auto-refresh ON (30s)' : 'Auto-refresh OFF'}
          >
            {#if autoRefresh}
              <span class="live-badge">Live</span>
            {:else}
              <span class="paused-badge">Paused</span>
            {/if}
          </button>
          <button class="refresh-btn" onclick={refresh} title="Refresh">&#x21bb;</button>
          <button class="panel-close" onclick={close}>&times;</button>
        </div>
      </div>

      <div class="filter-bar">
        <input
          class="branch-input"
          type="text"
          placeholder="Filter by branch..."
          bind:value={branchFilterInput}
          onkeydown={(e) => { if (e.key === 'Enter') applyBranchFilter(); }}
        />
        <button class="filter-apply-btn" onclick={applyBranchFilter}>Filter</button>
      </div>

      {#if relay.ciError}
        <div class="error-bar">{relay.ciError}</div>
      {/if}

      <div class="panel-body">
        {#if relay.ciRuns.length === 0}
          <div class="panel-empty">No CI runs found</div>
        {:else}
          {#each relay.ciRuns as run (run.id)}
            <button class="run-row" onclick={() => selectRun(run)}>
              <div class="run-top">
                <span class="run-status-icon {statusClass(run.status, run.conclusion)}">{statusIcon(run.status, run.conclusion)}</span>
                <span class="run-name">{run.name}</span>
                <span class="run-time">{timeAgo(run.createdAt)}</span>
              </div>
              <div class="run-title">{run.displayTitle}</div>
              <div class="run-meta">
                <span class="run-branch">{run.headBranch}</span>
                <span class="run-event">{eventLabel(run.event)}</span>
                <span class="run-actor">{run.actor}</span>
              </div>
              {#if run.conclusion}
                <div class="run-conclusion">
                  <span class="conclusion-badge {statusClass(run.status, run.conclusion)}">{conclusionLabel(run.conclusion)}</span>
                </div>
              {/if}
            </button>
            {#if expandedRun === run.id && relay.ciRunDetail?.id === run.id}
              {@const detail = relay.ciRunDetail}
              <div class="detail-block">
                <div class="detail-meta">
                  <span class="detail-sha">{detail.headSha.slice(0, 7)}</span>
                  <a class="detail-link" href={detail.url} target="_blank" rel="noopener noreferrer">View on GitHub</a>
                </div>

                {#if detail.jobs.length > 0}
                  <div class="detail-section-header">Jobs ({detail.jobs.length})</div>
                  {#each detail.jobs as job (job.id)}
                    <div class="job-row">
                      <span class="job-status-icon {statusClass(job.status, job.conclusion)}">{statusIcon(job.status, job.conclusion)}</span>
                      <span class="job-name">{job.name}</span>
                      {#if job.startedAt && job.completedAt}
                        <span class="job-duration">{formatDuration(job.startedAt, job.completedAt)}</span>
                      {/if}
                      {#if job.conclusion}
                        <span class="job-conclusion {statusClass(job.status, job.conclusion)}">{conclusionLabel(job.conclusion)}</span>
                      {/if}
                    </div>
                  {/each}
                {:else}
                  <div class="panel-empty">No jobs found</div>
                {/if}
              </div>
            {/if}
          {/each}
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .panel-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0,0,0,0.45);
    z-index: 200;
  }
  .panel {
    position: fixed;
    top: 0;
    right: 0;
    bottom: 0;
    width: min(480px, 95vw);
    background: var(--bg);
    border-left: 1px solid var(--border);
    box-shadow: -4px 0 24px rgba(0,0,0,0.4);
    animation: slide-in-right 0.2s ease-out;
    display: flex;
    flex-direction: column;
  }
  @keyframes slide-in-right {
    from { transform: translateX(100%); }
    to { transform: translateX(0); }
  }
  .panel-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 12px 16px;
    border-bottom: 1px solid var(--border);
  }
  .panel-title {
    font-weight: 600;
    font-size: 0.9rem;
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .title-icon {
    opacity: 0.8;
  }
  .header-actions {
    display: flex;
    gap: 8px;
    align-items: center;
  }
  .auto-refresh-btn {
    background: transparent;
    border: 1px solid var(--border);
    color: var(--text-secondary);
    padding: 2px 8px;
    border-radius: 4px;
    cursor: pointer;
    font-size: 0.65rem;
    font-family: var(--font-mono, monospace);
    transition: all 0.15s;
  }
  .auto-refresh-btn:hover {
    color: var(--text-primary);
    border-color: var(--text-secondary);
  }
  .auto-refresh-btn.active {
    border-color: #238636;
    color: #238636;
  }
  .live-badge {
    font-weight: 700;
    letter-spacing: 0.04em;
  }
  .paused-badge {
    opacity: 0.7;
  }
  .refresh-btn, .panel-close {
    background: transparent;
    border: none;
    color: var(--text-secondary);
    cursor: pointer;
    font-size: 1.1rem;
    padding: 2px 6px;
    border-radius: 4px;
  }
  .refresh-btn:hover, .panel-close:hover {
    color: var(--text-primary);
    background: var(--surface-hover);
  }
  .filter-bar {
    display: flex;
    gap: 4px;
    padding: 8px 16px;
    border-bottom: 1px solid var(--border);
  }
  .branch-input {
    flex: 1;
    background: var(--surface);
    border: 1px solid var(--border);
    color: var(--text-primary);
    padding: 4px 8px;
    border-radius: 4px;
    font-size: 0.7rem;
    font-family: var(--font-mono, monospace);
    outline: none;
    transition: border-color 0.15s;
  }
  .branch-input:focus {
    border-color: var(--accent);
  }
  .branch-input::placeholder {
    color: var(--text-tertiary);
  }
  .filter-apply-btn {
    background: transparent;
    border: 1px solid var(--border);
    color: var(--text-secondary);
    padding: 4px 10px;
    border-radius: 4px;
    cursor: pointer;
    font-size: 0.7rem;
    font-family: var(--font-mono, monospace);
    transition: all 0.15s;
  }
  .filter-apply-btn:hover {
    color: var(--text-primary);
    border-color: var(--text-secondary);
  }
  .error-bar {
    padding: 6px 16px;
    background: rgba(245, 160, 160, 0.15);
    color: #f5a0a0;
    font-size: 0.75rem;
    font-family: var(--font-mono, monospace);
  }
  .panel-body {
    flex: 1;
    overflow-y: auto;
    padding: 0;
  }
  .panel-empty {
    padding: 32px 16px;
    text-align: center;
    color: var(--text-secondary);
    font-size: 0.8rem;
  }

  /* ── Run rows ─────────────────────────────── */
  .run-row {
    display: flex;
    flex-direction: column;
    gap: 3px;
    padding: 10px 16px;
    width: 100%;
    text-align: left;
    background: transparent;
    border: none;
    color: var(--text-primary);
    cursor: pointer;
    border-bottom: 1px solid var(--border);
    transition: background 0.1s;
  }
  .run-row:hover { background: var(--surface-hover); }
  .run-top {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .run-status-icon {
    font-size: 0.85rem;
    width: 16px;
    text-align: center;
    flex-shrink: 0;
    font-weight: 700;
  }
  .run-name {
    font-family: var(--font-mono, monospace);
    font-size: 0.7rem;
    font-weight: 600;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .run-time {
    font-size: 0.65rem;
    color: var(--text-secondary);
    margin-left: auto;
    flex-shrink: 0;
  }
  .run-title {
    font-size: 0.8rem;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .run-meta {
    display: flex;
    gap: 8px;
    align-items: center;
    font-size: 0.65rem;
    color: var(--text-secondary);
  }
  .run-branch {
    font-family: var(--font-mono, monospace);
    font-size: 0.6rem;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    max-width: 180px;
  }
  .run-event {
    font-size: 0.6rem;
    font-weight: 600;
    padding: 1px 6px;
    border-radius: 8px;
    background: rgba(200, 200, 220, 0.15);
    color: var(--text-secondary);
    line-height: 1.4;
    text-transform: capitalize;
    flex-shrink: 0;
  }
  .run-actor {
    font-weight: 500;
    flex-shrink: 0;
  }
  .run-conclusion {
    margin-top: 2px;
  }
  .conclusion-badge {
    font-size: 0.6rem;
    font-weight: 700;
    padding: 1px 6px;
    border-radius: 8px;
    line-height: 1.4;
    text-transform: capitalize;
  }

  /* ── Status colors ─────────────────────────── */
  .status-success { color: #238636; }
  .status-failure { color: #da3633; }
  .status-in-progress { color: #d29922; }
  .status-queued { color: #768390; }

  .conclusion-badge.status-success { background: rgba(35, 134, 54, 0.2); color: #238636; }
  .conclusion-badge.status-failure { background: rgba(218, 54, 51, 0.2); color: #da3633; }
  .conclusion-badge.status-in-progress { background: rgba(210, 153, 34, 0.2); color: #d29922; }
  .conclusion-badge.status-queued { background: rgba(118, 131, 144, 0.2); color: #768390; }

  /* ── Detail block ────────────────────────── */
  .detail-block {
    margin: 0 8px 8px;
    border: 1px solid var(--border);
    border-radius: 4px;
    overflow: hidden;
    background: var(--bg);
  }
  .detail-meta {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 8px 12px;
    font-size: 0.7rem;
    border-bottom: 1px solid var(--border);
  }
  .detail-sha {
    font-family: var(--font-mono, monospace);
    font-weight: 600;
    color: var(--accent);
  }
  .detail-link {
    color: var(--text-secondary);
    font-size: 0.65rem;
    text-decoration: none;
    margin-left: auto;
    transition: color 0.15s;
  }
  .detail-link:hover {
    color: var(--accent);
    text-decoration: underline;
  }
  .detail-section-header {
    padding: 8px 12px 4px;
    font-size: 0.65rem;
    font-weight: 600;
    color: var(--text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.5px;
    border-top: 1px solid var(--border);
  }

  /* ── Job rows ──────────────────────────────── */
  .job-row {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 12px;
    font-size: 0.7rem;
    font-family: var(--font-mono, monospace);
  }
  .job-status-icon {
    font-size: 0.8rem;
    width: 16px;
    text-align: center;
    flex-shrink: 0;
    font-weight: 700;
  }
  .job-name {
    flex: 1;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .job-duration {
    font-size: 0.65rem;
    color: var(--text-secondary);
    flex-shrink: 0;
  }
  .job-conclusion {
    font-size: 0.6rem;
    font-weight: 700;
    padding: 1px 6px;
    border-radius: 8px;
    line-height: 1.4;
    flex-shrink: 0;
  }
  .job-conclusion.status-success { background: rgba(35, 134, 54, 0.2); }
  .job-conclusion.status-failure { background: rgba(218, 54, 51, 0.2); }
  .job-conclusion.status-in-progress { background: rgba(210, 153, 34, 0.2); }
  .job-conclusion.status-queued { background: rgba(118, 131, 144, 0.2); }
</style>
