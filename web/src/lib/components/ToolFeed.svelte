<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import { toolIcon } from '../utils/danger';

  let collapsed = $state(typeof window !== 'undefined' ? window.innerWidth < 768 : true);
  let feedEl: HTMLDivElement | undefined;

  let activities = $derived(relay.toolActivities);
  let runningCount = $derived(activities.filter((a) => !a.completedAt).length);

  // Auto-scroll to latest
  $effect(() => {
    activities.length;
    if (feedEl && !collapsed) {
      queueMicrotask(() => {
        feedEl!.scrollTop = feedEl!.scrollHeight;
      });
    }
  });

  function formatDuration(ms: number): string {
    if (ms < 1000) return `${ms}ms`;
    return `${(ms / 1000).toFixed(1)}s`;
  }

  function formatTime(date: Date): string {
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  }

  function describeInput(tool: string, input?: Record<string, unknown>): string {
    if (!input) return '';
    const toolLower = tool.toLowerCase();
    if (toolLower === 'bash' || toolLower === 'execute' || toolLower === 'shell') {
      const cmd = (input['command'] ?? input['tool_input']?.['command']) as string | undefined;
      return cmd ? cmd.slice(0, 80) : '';
    }
    if (toolLower === 'edit' || toolLower === 'replace' || toolLower === 'write' || toolLower === 'read' || toolLower === 'create') {
      const fp = (input['file_path'] ?? input['path'] ?? input['tool_input']?.['file_path']) as string | undefined;
      return fp ? fp.split('/').slice(-2).join('/') : '';
    }
    if (toolLower === 'glob' || toolLower === 'grep' || toolLower === 'search') {
      const pattern = (input['pattern'] ?? input['tool_input']?.['pattern']) as string | undefined;
      return pattern ? pattern.slice(0, 60) : '';
    }
    return '';
  }
</script>

{#if activities.length > 0}
  <div class="tool-feed">
    <button class="feed-header" onclick={() => collapsed = !collapsed}>
      <span class="feed-title">Tool Activity</span>
      {#if runningCount > 0}
        <span class="running-badge">{runningCount} running</span>
      {/if}
      <span class="feed-count">{activities.length}</span>
      <span class="toggle-arrow" class:collapsed>{collapsed ? '\u25B6' : '\u25BC'}</span>
    </button>

    {#if !collapsed}
      <div class="feed-list" bind:this={feedEl}>
        {#each activities as activity (activity.id)}
          <div class="feed-entry" class:running={!activity.completedAt} class:failed={activity.success === false}>
            <span class="entry-icon">{toolIcon(activity.tool)}</span>
            <span class="entry-tool">{activity.tool}</span>
            <span class="entry-desc">{describeInput(activity.tool, activity.input)}</span>
            <span class="entry-meta">
              {#if !activity.completedAt}
                <span class="status-dot running-dot"></span>
              {:else if activity.success}
                <span class="status-check">{'\u2713'}</span>
              {:else}
                <span class="status-fail">{'\u2717'}</span>
              {/if}
              {#if activity.duration != null}
                <span class="entry-duration">{formatDuration(activity.duration)}</span>
              {/if}
              <span class="entry-time">{formatTime(activity.startedAt)}</span>
            </span>
          </div>
        {/each}
      </div>
    {/if}
  </div>
{/if}

<style>
  .tool-feed {
    border-top: 1px solid var(--border);
    background: rgba(15, 15, 23, 0.6);
    flex-shrink: 0;
  }

  .feed-header {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    padding: var(--sp-xs) var(--sp-md);
    width: 100%;
    border: none;
    background: transparent;
    color: var(--text-secondary);
    font-family: var(--font-mono);
    font-size: 0.7rem;
    cursor: pointer;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
  .feed-header:hover { color: var(--text-primary); }

  .feed-title { flex: 1; text-align: left; }

  .running-badge {
    background: rgba(102, 179, 255, 0.2);
    color: rgb(102, 179, 255);
    padding: 1px 6px;
    border-radius: 8px;
    font-size: 0.65rem;
    animation: pulse-badge 1.5s ease-in-out infinite;
  }

  .feed-count {
    background: var(--surface);
    padding: 1px 6px;
    border-radius: 8px;
    font-size: 0.65rem;
  }

  .toggle-arrow {
    font-size: 0.6rem;
    transition: transform 0.15s;
  }

  .feed-list {
    max-height: 150px;
    overflow-y: auto;
    padding: 0 var(--sp-md) var(--sp-xs);
  }

  .feed-entry {
    display: flex;
    align-items: center;
    gap: var(--sp-xs);
    padding: 2px 0;
    font-family: var(--font-mono);
    font-size: 0.72rem;
    color: var(--text-secondary);
    opacity: 0.7;
  }
  .feed-entry.running { opacity: 1; }
  .feed-entry.failed { opacity: 0.6; }

  .entry-icon { font-size: 0.8rem; flex-shrink: 0; }
  .entry-tool {
    color: var(--text-primary);
    font-weight: 600;
    flex-shrink: 0;
  }
  .entry-desc {
    flex: 1;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    color: var(--text-tertiary);
  }
  .entry-meta {
    display: flex;
    align-items: center;
    gap: 4px;
    flex-shrink: 0;
    color: var(--text-tertiary);
    font-size: 0.65rem;
  }

  .status-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    display: inline-block;
  }
  .running-dot {
    background: rgb(102, 179, 255);
    animation: pulse-dot 1s ease-in-out infinite;
  }
  .status-check { color: rgb(77, 217, 115); }
  .status-fail { color: rgb(248, 113, 113); }

  .entry-duration { color: var(--text-tertiary); }
  .entry-time { color: var(--text-tertiary); }

  @keyframes pulse-dot {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.3; }
  }
  @keyframes pulse-badge {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.6; }
  }

  @media (max-width: 768px) {
    .entry-time { display: none; }
    .feed-list { max-height: 100px; }
  }
</style>
