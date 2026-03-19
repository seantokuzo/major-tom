<script lang="ts">
  import type { ApprovalRequest } from '../stores/relay.svelte';
  import type { ApprovalDecision } from '../protocol/messages';
  import { scoreToolDanger, dangerColor, toolIcon, type DangerLevel } from '../utils/danger';
  import { renderMarkdown } from '../utils/markdown';

  let { request, onDecision }: {
    request: ApprovalRequest;
    onDecision: (id: string, decision: ApprovalDecision) => void;
  } = $props();

  let expanded = $state(window.innerWidth >= 768);
  let swipeStartX = $state(0);
  let swipeDeltaX = $state(0);
  let isSwiping = $state(false);

  const SWIPE_THRESHOLD = 80;

  let danger = $derived(scoreToolDanger(request.tool, request.details));
  let borderColor = $derived(dangerColor(danger));
  let icon = $derived(toolIcon(request.tool));
  let toolLower = $derived(request.tool.toLowerCase());
  let timeStr = $derived(
    request.receivedAt.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })
  );

  // ── Tool-specific detail extraction ──────────────────────

  let bashCommand = $derived(
    (toolLower === 'bash' || toolLower === 'execute' || toolLower === 'shell')
      ? (request.details?.['command'] as string) ?? null
      : null
  );

  let bashCwd = $derived(
    (toolLower === 'bash' || toolLower === 'execute' || toolLower === 'shell')
      ? (request.details?.['cwd'] as string) ?? (request.details?.['working_directory'] as string) ?? null
      : null
  );

  let editFilePath = $derived(
    (toolLower === 'edit' || toolLower === 'replace')
      ? (request.details?.['file_path'] as string) ?? (request.details?.['path'] as string) ?? null
      : null
  );

  let editOldString = $derived(
    (toolLower === 'edit' || toolLower === 'replace')
      ? (request.details?.['old_string'] as string) ?? (request.details?.['old_str'] as string) ?? null
      : null
  );

  let editNewString = $derived(
    (toolLower === 'edit' || toolLower === 'replace')
      ? (request.details?.['new_string'] as string) ?? (request.details?.['new_str'] as string) ?? null
      : null
  );

  let editLineDelta = $derived(() => {
    if (!editOldString && !editNewString) return null;
    const oldLines = (editOldString ?? '').split('\n').length;
    const newLines = (editNewString ?? '').split('\n').length;
    return newLines - oldLines;
  });

  let writeFilePath = $derived(
    (toolLower === 'write' || toolLower === 'create')
      ? (request.details?.['file_path'] as string) ?? (request.details?.['path'] as string) ?? null
      : null
  );

  let writeContent = $derived(
    (toolLower === 'write' || toolLower === 'create')
      ? (request.details?.['content'] as string) ?? null
      : null
  );

  let writePreview = $derived(
    writeContent
      ? writeContent.split('\n').slice(0, 10).join('\n') + (writeContent.split('\n').length > 10 ? '\n...' : '')
      : null
  );

  let writeSize = $derived(
    writeContent ? writeContent.length : null
  );

  let readFilePath = $derived(
    toolLower === 'read'
      ? (request.details?.['file_path'] as string) ?? (request.details?.['path'] as string) ?? null
      : null
  );

  let readLineRange = $derived(() => {
    if (toolLower !== 'read') return null;
    const offset = request.details?.['offset'] as number | undefined;
    const limit = request.details?.['limit'] as number | undefined;
    if (offset != null || limit != null) {
      return `${offset ?? 0}${limit != null ? `-${(offset ?? 0) + limit}` : '+'}`;
    }
    return null;
  });

  let isGenericTool = $derived(
    !bashCommand && !editFilePath && !writeFilePath && !readFilePath
  );

  let detailsJson = $derived(
    isGenericTool && request.details && Object.keys(request.details).length > 0
      ? JSON.stringify(request.details, null, 2)
      : null
  );

  // ── Keyboard shortcut ────────────────────────────────────

  function handleKeydown(e: KeyboardEvent) {
    if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;
    if (e.key === 'a' || e.key === 'A') {
      e.preventDefault();
      onDecision(request.id, 'allow');
    } else if (e.key === 'd' || e.key === 'D') {
      e.preventDefault();
      onDecision(request.id, 'deny');
    }
  }

  // ── Swipe handling ───────────────────────────────────────

  function handleTouchStart(e: TouchEvent) {
    swipeStartX = e.touches[0].clientX;
    swipeDeltaX = 0;
    isSwiping = true;
  }

  function handleTouchMove(e: TouchEvent) {
    if (!isSwiping) return;
    swipeDeltaX = e.touches[0].clientX - swipeStartX;
  }

  function handleTouchEnd() {
    if (!isSwiping) return;
    isSwiping = false;
    if (swipeDeltaX > SWIPE_THRESHOLD) {
      onDecision(request.id, 'allow');
    } else if (swipeDeltaX < -SWIPE_THRESHOLD) {
      onDecision(request.id, 'deny');
    }
    swipeDeltaX = 0;
  }

  function escapeHtml(str: string): string {
    return str
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  }

  function formatFileSize(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }
</script>

<svelte:window onkeydown={handleKeydown} />

<div
  class="card"
  class:danger-high={danger === 'high'}
  class:danger-medium={danger === 'medium'}
  class:danger-normal={danger === 'normal'}
  style="--danger-color: {borderColor}; transform: translateX({isSwiping ? swipeDeltaX * 0.3 : 0}px)"
  ontouchstart={handleTouchStart}
  ontouchmove={handleTouchMove}
  ontouchend={handleTouchEnd}
>
  <!-- Header -->
  <div class="header">
    <div class="tool-info">
      <span class="tool-icon">{icon}</span>
      <span class="tool-name">{request.tool}</span>
      {#if danger === 'high'}
        <span class="danger-badge danger-badge-high" title="Potentially dangerous command">&#x26A0;&#xFE0F; DANGER</span>
      {:else if danger === 'medium'}
        <span class="danger-badge danger-badge-medium" title="Use caution">&#x26A0;&#xFE0F;</span>
      {/if}
    </div>
    <span class="timestamp">{timeStr}</span>
  </div>

  <!-- Description -->
  <div class="description">{request.description}</div>

  <!-- Expand/collapse toggle -->
  {#if request.details && Object.keys(request.details).length > 0}
    <button class="toggle-btn" onclick={() => expanded = !expanded}>
      <span class="toggle-arrow" class:expanded>{expanded ? '\u25BC' : '\u25B6'}</span>
      {expanded ? 'Hide details' : 'Show details'}
    </button>
  {/if}

  <!-- Details section -->
  {#if expanded}
    <div class="details">
      <!-- Bash tool -->
      {#if bashCommand}
        {#if bashCwd}
          <div class="detail-label">cwd: <span class="detail-path">{bashCwd}</span></div>
        {/if}
        <pre class="code-block bash-command"><code>{escapeHtml(bashCommand)}</code></pre>
      {/if}

      <!-- Edit tool -->
      {#if editFilePath}
        <div class="detail-label file-path">{editFilePath}</div>
        {#if editOldString != null || editNewString != null}
          <div class="diff-block">
            {#if editOldString}
              <pre class="diff-old"><code>{escapeHtml(editOldString)}</code></pre>
            {/if}
            {#if editNewString}
              <pre class="diff-new"><code>{escapeHtml(editNewString)}</code></pre>
            {/if}
          </div>
          {#if editLineDelta() != null}
            <span class="line-delta" class:positive={editLineDelta()! > 0} class:negative={editLineDelta()! < 0}>
              {editLineDelta()! > 0 ? '+' : ''}{editLineDelta()} lines
            </span>
          {/if}
        {/if}
      {/if}

      <!-- Write tool -->
      {#if writeFilePath}
        <div class="detail-label file-path">{writeFilePath}</div>
        {#if writeSize != null}
          <div class="detail-meta">{formatFileSize(writeSize)}</div>
        {/if}
        {#if writePreview}
          <pre class="code-block"><code>{escapeHtml(writePreview)}</code></pre>
        {/if}
      {/if}

      <!-- Read tool -->
      {#if readFilePath}
        <div class="detail-label file-path">{readFilePath}</div>
        {#if readLineRange()}
          <div class="detail-meta">Lines {readLineRange()}</div>
        {/if}
      {/if}

      <!-- Generic tool -->
      {#if detailsJson}
        <pre class="code-block json-block"><code>{escapeHtml(detailsJson)}</code></pre>
      {/if}
    </div>
  {/if}

  <!-- Swipe hints (visible during swipe) -->
  {#if isSwiping && Math.abs(swipeDeltaX) > 20}
    <div class="swipe-hint" class:swipe-allow={swipeDeltaX > 0} class:swipe-deny={swipeDeltaX < 0}>
      {swipeDeltaX > 0 ? 'Allow \u2192' : '\u2190 Deny'}
    </div>
  {/if}

  <!-- Actions -->
  <div class="actions">
    <button class="btn btn-allow" onclick={() => onDecision(request.id, 'allow')}>
      Allow
    </button>
    <button class="btn btn-allow-always" onclick={() => onDecision(request.id, 'allow_always')}>
      Always
    </button>
    <button class="btn btn-deny" onclick={() => onDecision(request.id, 'deny')}>
      Deny
    </button>
  </div>
  <div class="shortcut-hint">A = Allow &middot; D = Deny &middot; Swipe to decide</div>
</div>

<style>
  .card {
    background: var(--surface);
    border: 1px solid var(--danger-color, var(--border));
    border-left: 3px solid var(--danger-color, var(--border));
    border-radius: var(--r-md);
    padding: var(--sp-md);
    min-width: 300px;
    max-width: 420px;
    flex-shrink: 0;
    transition: transform 0.15s ease-out, border-color 0.2s;
    position: relative;
    overflow: hidden;
  }

  .danger-high {
    background: rgba(248, 113, 113, 0.06);
  }

  .danger-medium {
    background: rgba(251, 191, 36, 0.04);
  }

  /* Header */
  .header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: var(--sp-xs);
  }

  .tool-info {
    display: flex;
    align-items: center;
    gap: var(--sp-xs);
  }

  .tool-icon {
    font-size: 1rem;
  }

  .tool-name {
    font-family: var(--font-mono);
    font-size: 0.85rem;
    font-weight: 600;
    color: var(--accent);
  }

  .danger-badge {
    font-size: 0.65rem;
    font-weight: 700;
    padding: 1px 5px;
    border-radius: var(--r-sm);
    letter-spacing: 0.04em;
  }

  .danger-badge-high {
    background: rgba(248, 113, 113, 0.2);
    color: #f87171;
    border: 1px solid rgba(248, 113, 113, 0.3);
  }

  .danger-badge-medium {
    background: rgba(251, 191, 36, 0.15);
    color: #fbbf24;
    border: 1px solid rgba(251, 191, 36, 0.25);
  }

  .timestamp {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    color: var(--text-tertiary);
  }

  /* Description */
  .description {
    font-size: 0.8rem;
    color: var(--text-secondary);
    margin-bottom: var(--sp-sm);
    line-height: 1.4;
    max-height: 60px;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  /* Toggle */
  .toggle-btn {
    background: none;
    border: none;
    color: var(--text-tertiary);
    font-size: 0.7rem;
    font-family: var(--font-mono);
    cursor: pointer;
    padding: var(--sp-xs) 0;
    display: flex;
    align-items: center;
    gap: var(--sp-xs);
    transition: color 0.15s;
  }
  .toggle-btn:hover {
    color: var(--text-secondary);
  }

  .toggle-arrow {
    transition: transform 0.2s;
    display: inline-block;
    font-size: 0.6rem;
  }
  .toggle-arrow.expanded {
    transform: rotate(0deg);
  }

  /* Details */
  .details {
    margin: var(--sp-sm) 0;
    padding: var(--sp-sm);
    background: rgba(0, 0, 0, 0.3);
    border-radius: var(--r-sm);
    overflow: hidden;
  }

  .detail-label {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    color: var(--text-tertiary);
    margin-bottom: var(--sp-xs);
  }

  .file-path {
    color: var(--accent-dim);
    font-weight: 600;
    word-break: break-all;
  }

  .detail-path {
    color: var(--text-secondary);
    word-break: break-all;
  }

  .detail-meta {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    color: var(--text-tertiary);
    margin-bottom: var(--sp-xs);
  }

  /* Code blocks */
  .code-block {
    background: rgba(0, 0, 0, 0.4);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    padding: var(--sp-sm);
    overflow-x: auto;
    margin: var(--sp-xs) 0;
    max-height: 200px;
    overflow-y: auto;
  }

  .code-block code {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    color: var(--text-primary);
    white-space: pre-wrap;
    word-break: break-all;
  }

  .bash-command code {
    color: #e8e8f0;
  }

  /* Diff blocks */
  .diff-block {
    margin: var(--sp-xs) 0;
    border-radius: var(--r-sm);
    overflow: hidden;
    border: 1px solid var(--border);
  }

  .diff-old,
  .diff-new {
    margin: 0;
    padding: var(--sp-sm);
    overflow-x: auto;
    max-height: 120px;
    overflow-y: auto;
  }

  .diff-old {
    background: rgba(248, 113, 113, 0.08);
    border-bottom: 1px solid var(--border);
  }

  .diff-old code {
    font-family: var(--font-mono);
    font-size: 0.72rem;
    color: #fca5a5;
    white-space: pre-wrap;
    word-break: break-all;
  }

  .diff-new {
    background: rgba(74, 222, 128, 0.08);
  }

  .diff-new code {
    font-family: var(--font-mono);
    font-size: 0.72rem;
    color: #86efac;
    white-space: pre-wrap;
    word-break: break-all;
  }

  .line-delta {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    color: var(--text-tertiary);
    margin-top: var(--sp-xs);
    display: inline-block;
  }

  .line-delta.positive {
    color: #4ade80;
  }

  .line-delta.negative {
    color: #f87171;
  }

  .json-block {
    max-height: 150px;
  }

  /* Swipe hint */
  .swipe-hint {
    position: absolute;
    top: 50%;
    transform: translateY(-50%);
    font-family: var(--font-mono);
    font-size: 0.75rem;
    font-weight: 700;
    pointer-events: none;
    padding: var(--sp-xs) var(--sp-sm);
    border-radius: var(--r-sm);
  }

  .swipe-allow {
    right: var(--sp-sm);
    color: var(--allow);
    background: rgba(74, 222, 128, 0.15);
  }

  .swipe-deny {
    left: var(--sp-sm);
    color: var(--deny);
    background: rgba(248, 113, 113, 0.15);
  }

  /* Actions */
  .actions {
    display: flex;
    gap: var(--sp-sm);
    margin-top: var(--sp-sm);
  }

  .btn {
    flex: 1;
    padding: var(--sp-sm) var(--sp-md);
    border: none;
    border-radius: var(--r-sm);
    font-size: 0.8rem;
    font-weight: 600;
    cursor: pointer;
    transition: opacity 0.15s, transform 0.1s;
  }
  .btn:hover { opacity: 0.85; }
  .btn:active { opacity: 0.7; transform: scale(0.97); }

  .btn-allow { background: var(--allow); color: #000; }
  .btn-deny { background: var(--deny); color: #000; }

  .btn-allow-always {
    background: transparent;
    color: var(--allow);
    border: 1px solid var(--allow);
    opacity: 0.7;
  }
  .btn-allow-always:hover { opacity: 1; background: rgba(74, 222, 128, 0.1); }

  .shortcut-hint {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    color: var(--text-tertiary);
    text-align: center;
    margin-top: var(--sp-xs);
    opacity: 0.6;
  }

  /* Mobile adjustments */
  @media (max-width: 767px) {
    .card {
      min-width: 0;
      max-width: 100%;
      width: 100%;
    }

    .shortcut-hint {
      display: none;
    }
  }

  @media (min-width: 768px) {
    .swipe-hint {
      display: none;
    }
  }
</style>
