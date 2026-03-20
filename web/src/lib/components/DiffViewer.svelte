<script lang="ts">
  /**
   * DiffViewer — renders unified or side-by-side diffs for Edit/Write tool results.
   * Svelte 5 runes only ($state, $derived). Dark theme, mobile-friendly.
   */

  interface DiffLine {
    type: 'add' | 'remove' | 'context';
    content: string;
    oldLineNum: number | null;
    newLineNum: number | null;
  }

  interface Props {
    filePath: string;
    oldContent: string;
    newContent: string;
    /** Max lines before auto-collapsing (default 40) */
    collapseThreshold?: number;
  }

  let {
    filePath,
    oldContent,
    newContent,
    collapseThreshold = 40,
  }: Props = $props();

  let viewMode = $state<'unified' | 'side-by-side'>('unified');
  let expanded = $state(false);
  let copied = $state(false);

  // ── Diff computation ────────────────────────────────────────

  /**
   * LCS-based diff via dynamic programming. O(m·n) — suitable for typical edit sizes (< 500 lines).
   */
  const MAX_DIFF_LINES = 500;

  function computeDiff(oldStr: string, newStr: string): DiffLine[] {
    const oldLines = oldStr ? oldStr.split('\n') : [];
    const newLines = newStr ? newStr.split('\n') : [];

    // LCS via dynamic programming
    const m = oldLines.length;
    const n = newLines.length;

    // Too large for LCS — show as full replacement to avoid freezing the UI
    if (m > MAX_DIFF_LINES || n > MAX_DIFF_LINES) {
      return [
        ...oldLines.map((line, i) => ({ type: 'remove' as const, content: line, oldLineNum: i + 1, newLineNum: null })),
        ...newLines.map((line, i) => ({ type: 'add' as const, content: line, oldLineNum: null, newLineNum: i + 1 })),
      ];
    }

    // For empty old content (Write tool), everything is an addition
    if (m === 0) {
      return newLines.map((line, i) => ({
        type: 'add' as const,
        content: line,
        oldLineNum: null,
        newLineNum: i + 1,
      }));
    }

    // For empty new content, everything is a removal
    if (n === 0) {
      return oldLines.map((line, i) => ({
        type: 'remove' as const,
        content: line,
        oldLineNum: i + 1,
        newLineNum: null,
      }));
    }

    // Build LCS table
    const dp: number[][] = Array.from({ length: m + 1 }, () =>
      new Array(n + 1).fill(0)
    );
    for (let i = 1; i <= m; i++) {
      for (let j = 1; j <= n; j++) {
        if (oldLines[i - 1] === newLines[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = Math.max(dp[i - 1][j], dp[i][j - 1]);
        }
      }
    }

    // Backtrack to produce diff
    const result: DiffLine[] = [];
    let i = m;
    let j = n;

    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && oldLines[i - 1] === newLines[j - 1]) {
        result.push({
          type: 'context',
          content: oldLines[i - 1],
          oldLineNum: i,
          newLineNum: j,
        });
        i--;
        j--;
      } else if (j > 0 && (i === 0 || dp[i][j - 1] >= dp[i - 1][j])) {
        result.push({
          type: 'add',
          content: newLines[j - 1],
          oldLineNum: null,
          newLineNum: j,
        });
        j--;
      } else {
        result.push({
          type: 'remove',
          content: oldLines[i - 1],
          oldLineNum: i,
          newLineNum: null,
        });
        i--;
      }
    }

    return result.reverse();
  }

  let diffLines = $derived(computeDiff(oldContent, newContent));
  let isLargeDiff = $derived(diffLines.length > collapseThreshold);
  let isCollapsed = $derived(isLargeDiff && !expanded);
  let visibleLines = $derived(
    isCollapsed ? diffLines.slice(0, collapseThreshold) : diffLines
  );

  let addCount = $derived(diffLines.filter((l) => l.type === 'add').length);
  let removeCount = $derived(diffLines.filter((l) => l.type === 'remove').length);

  // Side-by-side pairs for split view
  interface SidePair {
    left: DiffLine | null;
    right: DiffLine | null;
  }

  let sidePairs = $derived.by((): SidePair[] => {
    const pairs: SidePair[] = [];
    const removeQueue: DiffLine[] = [];
    const addQueue: DiffLine[] = [];

    function flushQueues() {
      const max = Math.max(removeQueue.length, addQueue.length);
      for (let k = 0; k < max; k++) {
        pairs.push({
          left: removeQueue[k] ?? null,
          right: addQueue[k] ?? null,
        });
      }
      removeQueue.length = 0;
      addQueue.length = 0;
    }

    for (const line of diffLines) {
      if (line.type === 'context') {
        flushQueues();
        pairs.push({ left: line, right: line });
      } else if (line.type === 'remove') {
        removeQueue.push(line);
      } else {
        addQueue.push(line);
      }
    }
    flushQueues();
    return pairs;
  });

  let visiblePairs = $derived(
    isCollapsed ? sidePairs.slice(0, collapseThreshold) : sidePairs
  );

  // ── File info ───────────────────────────────────────────────

  let fileName = $derived(filePath.split('/').pop() ?? filePath);

  // ── Actions ─────────────────────────────────────────────────

  async function copyNewContent() {
    try {
      await navigator.clipboard.writeText(newContent);
      copied = true;
      setTimeout(() => (copied = false), 2000);
    } catch {
      // Clipboard API not available
    }
  }
</script>

<div class="diff-viewer">
  <!-- Header -->
  <div class="diff-header">
    <div class="diff-file-info">
      <span class="diff-icon">~</span>
      <span class="diff-filename" title={filePath}>{fileName}</span>
      <span class="diff-path" title={filePath}>{filePath}</span>
    </div>
    <div class="diff-stats">
      {#if addCount > 0}
        <span class="stat-add">+{addCount}</span>
      {/if}
      {#if removeCount > 0}
        <span class="stat-remove">-{removeCount}</span>
      {/if}
    </div>
    <div class="diff-actions">
      <button
        class="diff-btn"
        class:active={viewMode === 'unified'}
        onclick={() => (viewMode = 'unified')}
        title="Unified view"
        aria-label="Unified view"
        aria-pressed={viewMode === 'unified'}
      >U</button>
      <button
        class="diff-btn"
        class:active={viewMode === 'side-by-side'}
        onclick={() => (viewMode = 'side-by-side')}
        title="Side-by-side view"
        aria-label="Side-by-side view"
        aria-pressed={viewMode === 'side-by-side'}
      >S</button>
      <button class="diff-btn" onclick={copyNewContent} title="Copy new content" aria-label={copied ? 'Copied' : 'Copy new content'}>
        {copied ? 'ok' : 'cp'}
      </button>
    </div>
  </div>

  <!-- Diff body -->
  <div class="diff-body" class:collapsed={isCollapsed}>
    {#if viewMode === 'unified'}
      <table class="diff-table unified">
        <tbody>
          {#each visibleLines as line}
            <tr class="diff-line diff-line-{line.type}">
              <td class="line-num old-num">{line.oldLineNum ?? ''}</td>
              <td class="line-num new-num">{line.newLineNum ?? ''}</td>
              <td class="line-marker">
                {#if line.type === 'add'}+{:else if line.type === 'remove'}-{:else}&nbsp;{/if}
              </td>
              <td class="line-content">{line.content}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    {:else}
      <table class="diff-table side-by-side">
        <tbody>
          {#each visiblePairs as pair}
            <tr class="diff-line">
              <!-- Left (old) -->
              <td class="line-num">{pair.left?.oldLineNum ?? ''}</td>
              <td
                class="line-content side-content"
                class:diff-line-remove={pair.left?.type === 'remove'}
                class:diff-line-context={pair.left?.type === 'context'}
                class:diff-line-empty={!pair.left}
              >{pair.left?.content ?? ''}</td>
              <!-- Right (new) -->
              <td class="line-num">{pair.right?.newLineNum ?? ''}</td>
              <td
                class="line-content side-content"
                class:diff-line-add={pair.right?.type === 'add'}
                class:diff-line-context={pair.right?.type === 'context'}
                class:diff-line-empty={!pair.right}
              >{pair.right?.content ?? ''}</td>
            </tr>
          {/each}
        </tbody>
      </table>
    {/if}
  </div>

  <!-- Collapse toggle -->
  {#if isLargeDiff}
    <button class="diff-expand-btn" onclick={() => (expanded = !expanded)}>
      {expanded
        ? `Collapse (${diffLines.length} lines)`
        : `Show all ${diffLines.length} lines (+${diffLines.length - collapseThreshold} more)`}
    </button>
  {/if}
</div>

<style>
  .diff-viewer {
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    overflow: hidden;
    margin: var(--sp-xs) 0;
    font-family: var(--font-mono);
    font-size: 0.75rem;
    line-height: 1.5;
    background: #0d0d18;
  }

  /* ── Header ──────────────────────────────────────────────── */

  .diff-header {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    padding: var(--sp-xs) var(--sp-sm);
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    flex-wrap: wrap;
  }

  .diff-file-info {
    display: flex;
    align-items: center;
    gap: var(--sp-xs);
    min-width: 0;
    flex: 1;
  }

  .diff-icon {
    color: var(--accent);
    font-weight: 700;
    flex-shrink: 0;
  }

  .diff-filename {
    color: var(--text-primary);
    font-weight: 600;
    white-space: nowrap;
  }

  .diff-path {
    color: var(--text-tertiary);
    font-size: 0.65rem;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    display: none;
  }

  /* Show path on wider screens */
  @media (min-width: 600px) {
    .diff-path {
      display: inline;
    }
  }

  .diff-stats {
    display: flex;
    gap: var(--sp-xs);
    flex-shrink: 0;
  }

  .stat-add {
    color: var(--allow);
    font-weight: 600;
  }

  .stat-remove {
    color: var(--deny);
    font-weight: 600;
  }

  .diff-actions {
    display: flex;
    gap: 2px;
    flex-shrink: 0;
  }

  .diff-btn {
    padding: 1px 6px;
    border: 1px solid var(--border);
    border-radius: 3px;
    background: transparent;
    color: var(--text-tertiary);
    font-family: var(--font-mono);
    font-size: 0.65rem;
    cursor: pointer;
    transition: all 0.15s;
  }

  .diff-btn:hover {
    color: var(--text-primary);
    border-color: var(--text-tertiary);
  }

  .diff-btn.active {
    color: var(--accent);
    border-color: var(--accent);
  }

  /* ── Diff body ───────────────────────────────────────────── */

  .diff-body {
    overflow-x: auto;
    -webkit-overflow-scrolling: touch;
    max-height: 600px;
    overflow-y: auto;
  }

  .diff-body.collapsed {
    max-height: none;
    overflow-y: hidden;
  }

  .diff-table {
    width: 100%;
    border-collapse: collapse;
    table-layout: fixed;
  }

  .diff-table.side-by-side {
    /* 4 cols: num + content + num + content */
  }

  .diff-line {
    border: none;
  }

  .line-num {
    width: 40px;
    min-width: 32px;
    padding: 0 4px;
    text-align: right;
    color: var(--text-tertiary);
    user-select: none;
    vertical-align: top;
    font-size: 0.65rem;
    opacity: 0.6;
  }

  .line-marker {
    width: 16px;
    min-width: 16px;
    padding: 0 2px;
    text-align: center;
    user-select: none;
    vertical-align: top;
    font-weight: 700;
  }

  .line-content {
    padding: 0 var(--sp-sm);
    white-space: pre;
    overflow-wrap: normal;
    vertical-align: top;
  }

  .side-content {
    width: 50%;
  }

  /* ── Line type colors ────────────────────────────────────── */

  .diff-line-add {
    background: rgba(74, 222, 128, 0.08);
  }

  .diff-line-add .line-marker,
  .diff-line-add .line-content,
  td.diff-line-add {
    color: #a3e6b7;
  }

  .diff-line-remove {
    background: rgba(248, 113, 113, 0.08);
  }

  .diff-line-remove .line-marker,
  .diff-line-remove .line-content,
  td.diff-line-remove {
    color: #f5a0a0;
  }

  .diff-line-context {
    background: transparent;
  }

  .diff-line-context .line-content,
  td.diff-line-context {
    color: var(--text-secondary);
  }

  .diff-line-empty {
    background: rgba(42, 42, 58, 0.3);
  }

  td.diff-line-empty {
    color: transparent;
  }

  /* ── Expand button ───────────────────────────────────────── */

  .diff-expand-btn {
    display: block;
    width: 100%;
    padding: var(--sp-xs) var(--sp-sm);
    border: none;
    border-top: 1px solid var(--border);
    background: var(--surface);
    color: var(--accent);
    font-family: var(--font-mono);
    font-size: 0.7rem;
    cursor: pointer;
    text-align: center;
    transition: background 0.15s;
  }

  .diff-expand-btn:hover {
    background: var(--surface-hover);
  }
</style>
