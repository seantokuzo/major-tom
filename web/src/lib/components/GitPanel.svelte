<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import type { GitStatusEntry, GitLogEntry } from '../protocol/messages';

  type Tab = 'status' | 'log' | 'branches';
  let activeTab = $state<Tab>('status');
  let expandedFile = $state<string | null>(null);
  let expandedCommit = $state<string | null>(null);

  function close() {
    relay.gitPanelOpen = false;
    activeTab = 'status';
    expandedFile = null;
    expandedCommit = null;
    relay.gitError = null;
  }

  $effect(() => {
    if (!relay.gitPanelOpen) return;
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') close();
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  function refresh() {
    relay.requestGitStatus();
    relay.requestGitLog();
    relay.requestGitBranches();
  }

  function selectFile(entry: GitStatusEntry) {
    const key = `${entry.path}:${entry.staged}`;
    if (expandedFile === key) {
      expandedFile = null;
      return;
    }
    expandedFile = key;
    relay.requestGitDiff(entry.path, entry.staged);
  }

  function selectCommit(entry: GitLogEntry) {
    if (expandedCommit === entry.hash) {
      expandedCommit = null;
      relay.gitShowCommit = null;
      return;
    }
    expandedCommit = entry.hash;
    relay.requestGitShow(entry.hash);
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

  function statusColor(status: GitStatusEntry['status']): string {
    switch (status) {
      case 'added': case 'untracked': return '#a3e6b7';
      case 'modified': case 'renamed': case 'copied': return '#f0c674';
      case 'deleted': return '#f5a0a0';
      default: return 'var(--text-secondary)';
    }
  }

  function statusLabel(status: GitStatusEntry['status']): string {
    return status[0]!.toUpperCase();
  }

  // Group status entries
  let stagedEntries = $derived(relay.gitStatus.filter(e => e.staged));
  let unstagedEntries = $derived(relay.gitStatus.filter(e => !e.staged && e.status !== 'untracked'));
  let untrackedEntries = $derived(relay.gitStatus.filter(e => e.status === 'untracked'));

  // Parse raw diff for display
  function parseDiffLines(diff: string): Array<{ type: 'add' | 'remove' | 'context' | 'header'; text: string }> {
    return diff.split('\n').map(line => {
      if (line.startsWith('+++') || line.startsWith('---') || line.startsWith('diff ') || line.startsWith('index ') || line.startsWith('@@')) {
        return { type: 'header' as const, text: line };
      }
      if (line.startsWith('+')) return { type: 'add' as const, text: line };
      if (line.startsWith('-')) return { type: 'remove' as const, text: line };
      return { type: 'context' as const, text: line };
    });
  }
</script>

{#if relay.gitPanelOpen}
  <div class="panel-backdrop" role="button" tabindex="-1" onclick={close} onkeydown={(e) => { if (e.key === 'Escape') close(); }}>
    <div class="panel" role="dialog" aria-label="Git panel" onclick={(e) => e.stopPropagation()} onkeydown={() => {}}>
      <div class="panel-header">
        <span class="panel-title">
          Git
          {#if relay.gitBranch}
            <span class="branch-badge">{relay.gitBranch}</span>
          {/if}
        </span>
        <div class="header-actions">
          <button class="refresh-btn" onclick={refresh} title="Refresh">&#x21bb;</button>
          <button class="panel-close" onclick={close}>&times;</button>
        </div>
      </div>

      <div class="tabs">
        <button class="tab" class:active={activeTab === 'status'} onclick={() => activeTab = 'status'}>
          Status
          {#if relay.gitStatus.length > 0}
            <span class="tab-count">{relay.gitStatus.length}</span>
          {/if}
        </button>
        <button class="tab" class:active={activeTab === 'log'} onclick={() => activeTab = 'log'}>Log</button>
        <button class="tab" class:active={activeTab === 'branches'} onclick={() => activeTab = 'branches'}>Branches</button>
      </div>

      {#if relay.gitError}
        <div class="error-bar">{relay.gitError}</div>
      {/if}

      <div class="panel-body">
        {#if activeTab === 'status'}
          {#if relay.gitStatus.length === 0}
            <div class="panel-empty">Working tree clean</div>
          {:else}
            {#if stagedEntries.length > 0}
              <div class="group-header">Staged ({stagedEntries.length})</div>
              {#each stagedEntries as entry (entry.path + ':staged')}
                <button class="file-row" onclick={() => selectFile(entry)}>
                  <span class="status-badge" style="color: {statusColor(entry.status)}">{statusLabel(entry.status)}</span>
                  <span class="file-path" title={entry.path}>{entry.path}</span>
                  <span class="expand-icon">{expandedFile === `${entry.path}:true` ? '\u25BE' : '\u25B8'}</span>
                </button>
                {#if expandedFile === `${entry.path}:true` && relay.gitDiff && relay.gitDiffPath === entry.path && relay.gitDiffStaged}
                  <div class="diff-block">
                    {#each parseDiffLines(relay.gitDiff) as line}
                      <div class="diff-line {line.type}">{line.text}</div>
                    {/each}
                  </div>
                {/if}
              {/each}
            {/if}

            {#if unstagedEntries.length > 0}
              <div class="group-header">Unstaged ({unstagedEntries.length})</div>
              {#each unstagedEntries as entry (entry.path + ':unstaged')}
                <button class="file-row" onclick={() => selectFile(entry)}>
                  <span class="status-badge" style="color: {statusColor(entry.status)}">{statusLabel(entry.status)}</span>
                  <span class="file-path" title={entry.path}>{entry.path}</span>
                  <span class="expand-icon">{expandedFile === `${entry.path}:false` ? '\u25BE' : '\u25B8'}</span>
                </button>
                {#if expandedFile === `${entry.path}:false` && relay.gitDiff && relay.gitDiffPath === entry.path && !relay.gitDiffStaged}
                  <div class="diff-block">
                    {#each parseDiffLines(relay.gitDiff) as line}
                      <div class="diff-line {line.type}">{line.text}</div>
                    {/each}
                  </div>
                {/if}
              {/each}
            {/if}

            {#if untrackedEntries.length > 0}
              <div class="group-header">Untracked ({untrackedEntries.length})</div>
              {#each untrackedEntries as entry (entry.path + ':untracked')}
                <div class="file-row untracked">
                  <span class="status-badge" style="color: {statusColor(entry.status)}">?</span>
                  <span class="file-path" title={entry.path}>{entry.path}</span>
                </div>
              {/each}
            {/if}
          {/if}

        {:else if activeTab === 'log'}
          {#if relay.gitLog.length === 0}
            <div class="panel-empty">No commits</div>
          {:else}
            {#each relay.gitLog as entry (entry.hash)}
              <button class="commit-row" onclick={() => selectCommit(entry)}>
                <div class="commit-top">
                  <span class="commit-hash">{entry.shortHash}</span>
                  <span class="commit-time">{timeAgo(entry.date)}</span>
                </div>
                <div class="commit-message">{entry.message}</div>
                <div class="commit-author">{entry.author}</div>
              </button>
              {#if expandedCommit === entry.hash && relay.gitShowCommit && relay.gitShowCommit.hash === entry.hash}
                <div class="diff-block">
                  <div class="commit-detail-header">
                    <div><strong>{relay.gitShowCommit.message}</strong></div>
                    <div class="commit-detail-meta">{relay.gitShowCommit.author} &middot; {timeAgo(relay.gitShowCommit.date)}</div>
                  </div>
                  {#each parseDiffLines(relay.gitShowCommit.diff) as line}
                    <div class="diff-line {line.type}">{line.text}</div>
                  {/each}
                </div>
              {/if}
            {/each}
          {/if}

        {:else if activeTab === 'branches'}
          {#if relay.gitBranches.length === 0}
            <div class="panel-empty">No branches</div>
          {:else}
            <div class="group-header">Local</div>
            {#each relay.gitBranches.filter(b => !b.remote) as branch (branch.name)}
              <div class="branch-row" class:current={branch.current}>
                <span class="branch-name">
                  {#if branch.current}<span class="current-marker">*</span>{/if}
                  {branch.name}
                </span>
                <span class="branch-meta">
                  {#if branch.upstream}
                    <span class="upstream" title={branch.upstream}>{branch.upstream}</span>
                  {/if}
                  {#if branch.ahead}
                    <span class="ahead">+{branch.ahead}</span>
                  {/if}
                  {#if branch.behind}
                    <span class="behind">-{branch.behind}</span>
                  {/if}
                </span>
              </div>
            {/each}

            {#if relay.gitBranches.some(b => b.remote)}
              <div class="group-header">Remote</div>
              {#each relay.gitBranches.filter(b => b.remote) as branch (branch.name)}
                <div class="branch-row remote">
                  <span class="branch-name">{branch.name}</span>
                </div>
              {/each}
            {/if}
          {/if}
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
  .branch-badge {
    font-size: 0.7rem;
    font-family: var(--font-mono, monospace);
    background: var(--surface-hover);
    padding: 2px 8px;
    border-radius: 4px;
    color: var(--accent);
  }
  .header-actions {
    display: flex;
    gap: 8px;
    align-items: center;
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
  .tabs {
    display: flex;
    border-bottom: 1px solid var(--border);
    padding: 0 16px;
  }
  .tab {
    background: transparent;
    border: none;
    color: var(--text-secondary);
    padding: 8px 12px;
    cursor: pointer;
    font-size: 0.75rem;
    font-family: var(--font-mono, monospace);
    border-bottom: 2px solid transparent;
    display: flex;
    align-items: center;
    gap: 4px;
    transition: all 0.15s;
  }
  .tab:hover { color: var(--text-primary); }
  .tab.active {
    color: var(--accent);
    border-bottom-color: var(--accent);
  }
  .tab-count {
    background: var(--surface-hover);
    padding: 0 5px;
    border-radius: 8px;
    font-size: 0.65rem;
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
    padding: 8px 0;
  }
  .panel-empty {
    padding: 32px 16px;
    text-align: center;
    color: var(--text-secondary);
    font-size: 0.8rem;
  }
  .group-header {
    padding: 8px 16px 4px;
    font-size: 0.65rem;
    font-weight: 600;
    color: var(--text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }
  .file-row {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 16px;
    width: 100%;
    text-align: left;
    background: transparent;
    border: none;
    color: var(--text-primary);
    cursor: pointer;
    font-family: var(--font-mono, monospace);
    font-size: 0.75rem;
    transition: background 0.1s;
  }
  .file-row:hover { background: var(--surface-hover); }
  .file-row.untracked { cursor: default; opacity: 0.7; }
  .status-badge {
    font-weight: 700;
    font-size: 0.7rem;
    width: 14px;
    text-align: center;
    flex-shrink: 0;
  }
  .file-path {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    flex: 1;
  }
  .expand-icon {
    color: var(--text-secondary);
    font-size: 0.65rem;
    flex-shrink: 0;
  }
  .diff-block {
    max-height: 400px;
    overflow: auto;
    margin: 0 8px 8px;
    border: 1px solid var(--border);
    border-radius: 4px;
    font-family: var(--font-mono, monospace);
    font-size: 0.7rem;
    line-height: 1.5;
    background: var(--bg);
  }
  .diff-line {
    padding: 0 8px;
    white-space: pre;
    overflow-x: auto;
  }
  .diff-line.add { background: rgba(163, 230, 183, 0.12); color: #a3e6b7; }
  .diff-line.remove { background: rgba(245, 160, 160, 0.12); color: #f5a0a0; }
  .diff-line.header { color: var(--accent); font-weight: 600; }
  .diff-line.context { color: var(--text-secondary); }
  .commit-row {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 8px 16px;
    width: 100%;
    text-align: left;
    background: transparent;
    border: none;
    color: var(--text-primary);
    cursor: pointer;
    border-bottom: 1px solid var(--border);
    transition: background 0.1s;
  }
  .commit-row:hover { background: var(--surface-hover); }
  .commit-top {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  .commit-hash {
    font-family: var(--font-mono, monospace);
    font-size: 0.7rem;
    color: var(--accent);
  }
  .commit-time {
    font-size: 0.65rem;
    color: var(--text-secondary);
  }
  .commit-message {
    font-size: 0.8rem;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .commit-author {
    font-size: 0.65rem;
    color: var(--text-secondary);
  }
  .commit-detail-header {
    padding: 8px;
    border-bottom: 1px solid var(--border);
  }
  .commit-detail-meta {
    font-size: 0.65rem;
    color: var(--text-secondary);
    margin-top: 4px;
  }
  .branch-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 6px 16px;
    font-family: var(--font-mono, monospace);
    font-size: 0.75rem;
  }
  .branch-row.current {
    color: var(--accent);
    font-weight: 600;
  }
  .branch-row.remote {
    opacity: 0.6;
  }
  .branch-name {
    display: flex;
    align-items: center;
    gap: 4px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .current-marker {
    color: var(--accent);
    font-weight: 700;
  }
  .branch-meta {
    display: flex;
    gap: 6px;
    align-items: center;
    font-size: 0.65rem;
    flex-shrink: 0;
  }
  .upstream {
    color: var(--text-secondary);
    max-width: 100px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .ahead { color: #a3e6b7; }
  .behind { color: #f5a0a0; }
</style>
