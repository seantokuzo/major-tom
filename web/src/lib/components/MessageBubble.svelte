<script lang="ts">
  import type { ChatMessage } from '../stores/relay.svelte';
  import { renderMarkdown, attachCopyHandlers } from '../utils/markdown';
  import DiffViewer from './DiffViewer.svelte';

  let { message }: { message: ChatMessage } = $props();
  let mdEl: HTMLDivElement | undefined;

  // ── Relative timestamp for user messages ──────────────────
  let now = $state(Date.now());

  function formatRelativeTime(date: Date): string {
    const secs = Math.floor((now - date.getTime()) / 1000);
    if (secs < 10) return 'just now';
    if (secs < 60) return `${secs}s ago`;
    const mins = Math.floor(secs / 60);
    if (mins < 60) return `${mins}m ago`;
    const hrs = Math.floor(mins / 60);
    if (hrs < 24) return `${hrs}h ago`;
    return `${Math.floor(hrs / 24)}d ago`;
  }

  $effect(() => {
    if (message.role !== 'user') return;
    now = Date.now();
    const id = setInterval(() => { now = Date.now(); }, 15_000);
    return () => clearInterval(id);
  });

  let relativeTime = $derived(
    message.role === 'user' ? formatRelativeTime(message.timestamp) : ''
  );

  // Attach copy handlers after markdown renders / updates
  $effect(() => {
    rendered; // reactive dependency
    if (mdEl) queueMicrotask(() => attachCopyHandlers(mdEl!));
  });

  let rendered = $derived(
    message.role === 'assistant' ? renderMarkdown(message.content) : ''
  );

  // ── Diff detection for Edit/Write tool messages ──────────────

  /** Tool names that produce diffs we can render (exact match, case-insensitive) */
  const EDIT_TOOL_SET = new Set(['edit', 'file_edit', 'editfile']);
  const WRITE_TOOL_SET = new Set(['write', 'file_write', 'writefile', 'createfile']);

  interface DiffData {
    filePath: string;
    oldContent: string;
    newContent: string;
  }

  // ── Collapsible tool state ─────────────────────────────────

  /** Icons for common tools */
  const TOOL_ICONS: Record<string, string> = {
    Bash: '$', Read: '>>', Write: '<<', Edit: '~=',
    Grep: '??', Glob: '**', WebFetch: '{}', WebSearch: '??',
    Agent: '=>', TodoRead: '[]', TodoWrite: '[x]',
  };

  let toolExpanded = $state(false);

  let toolName = $derived(message.toolMeta?.tool ?? '');
  let toolIcon = $derived(TOOL_ICONS[toolName] ?? '>>');
  let toolSuccess = $derived(message.toolMeta?.success);
  let isLongContent = $derived(message.content.length > 100);

  let diffData = $derived.by((): DiffData | null => {
    if (message.role !== 'tool' || !message.toolMeta) return null;
    const { tool, input } = message.toolMeta;
    if (!input) return null;

    const filePath = (input['file_path'] ?? input['path'] ?? input['filePath'] ?? '') as string;
    if (!filePath) return null;

    if (EDIT_TOOL_SET.has(tool.toLowerCase())) {
      const oldStr = (input['old_string'] ?? input['oldString'] ?? input['old_str'] ?? '') as string;
      const newStr = (input['new_string'] ?? input['newString'] ?? input['new_str'] ?? '') as string;
      if (oldStr || newStr) {
        return { filePath, oldContent: oldStr, newContent: newStr };
      }
    }

    if (WRITE_TOOL_SET.has(tool.toLowerCase())) {
      const content = (input['content'] ?? input['file_text'] ?? '') as string;
      if (content) {
        return { filePath, oldContent: '', newContent: content };
      }
    }

    return null;
  });
</script>

<div class="msg msg-{message.role}">
  {#if message.role === 'user'}
    <span class="user-prompt">&gt;</span>
    <span class="user-text">{message.content}</span>
    <span class="user-timestamp">{relativeTime}</span>
  {:else if message.role === 'assistant'}
    <div class="assistant-text markdown" bind:this={mdEl}>{@html rendered}</div>
  {:else if message.role === 'tool'}
    {#if diffData}
      <DiffViewer
        filePath={diffData.filePath}
        oldContent={diffData.oldContent}
        newContent={diffData.newContent}
      />
    {:else}
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <div class="tool-row" onclick={() => { toolExpanded = !toolExpanded; }}>
        <span class="tool-icon-badge">{toolIcon}</span>
        <span class="tool-name">{toolName}</span>
        {#if toolSuccess === true}
          <span class="tool-status tool-ok">ok</span>
        {:else if toolSuccess === false}
          <span class="tool-status tool-fail">err</span>
        {/if}
        {#if isLongContent}
          <span class="tool-chevron" class:tool-chevron-open={toolExpanded}>&rsaquo;</span>
        {/if}
      </div>
      {#if !isLongContent || toolExpanded}
        <div class="tool-content">
          <span class="tool-text">{message.content}</span>
        </div>
      {/if}
    {/if}
  {:else}
    <span class="system-text">{message.content}</span>
  {/if}
</div>

<style>
  .msg {
    font-family: var(--font-mono);
    font-size: 0.85rem;
    line-height: 1.5;
    max-width: 100%;
    word-wrap: break-word;
  }

  /* User messages — look like typed commands */
  .msg-user {
    display: flex;
    gap: var(--sp-sm);
    padding: var(--sp-xs) 0;
    color: var(--text-primary);
  }

  .user-prompt {
    color: var(--accent);
    flex-shrink: 0;
    font-weight: 700;
  }

  .user-text {
    white-space: pre-wrap;
    flex: 1;
    min-width: 0;
  }

  .user-timestamp {
    font-size: 0.65rem;
    color: var(--text-tertiary);
    flex-shrink: 0;
    align-self: flex-start;
    margin-top: 2px;
  }

  /* Assistant messages — continuous text blocks */
  .msg-assistant {
    padding: var(--sp-xs) 0;
    color: var(--text-secondary);
    border-left: 2px solid var(--border);
    padding-left: var(--sp-md);
    margin-left: var(--sp-xs);
  }

  .assistant-text {
    white-space: normal;
  }

  /* Tool messages — collapsible inline status */
  .msg-tool {
    padding: 1px 0;
  }

  .tool-row {
    display: inline-flex;
    align-items: center;
    gap: var(--sp-xs);
    cursor: pointer;
    padding: 1px 0;
    user-select: none;
  }

  .tool-icon-badge {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    font-weight: 700;
    color: var(--accent);
    background: rgba(212, 168, 83, 0.1);
    padding: 0 3px;
    border-radius: 2px;
    letter-spacing: -0.02em;
  }

  .tool-name {
    font-size: 0.72rem;
    color: var(--text-tertiary);
    font-weight: 500;
  }

  .tool-status {
    font-size: 0.6rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    padding: 0 3px;
    border-radius: 2px;
  }
  .tool-ok { color: var(--allow); background: rgba(74, 222, 128, 0.1); }
  .tool-fail { color: var(--deny); background: rgba(248, 113, 113, 0.1); }

  .tool-chevron {
    font-size: 0.8rem;
    color: var(--text-tertiary);
    transition: transform 0.15s;
    display: inline-block;
  }
  .tool-chevron-open {
    transform: rotate(90deg);
  }

  .tool-content {
    padding-left: var(--sp-lg);
  }

  .tool-text {
    font-size: 0.75rem;
    color: var(--text-tertiary);
    white-space: pre-wrap;
  }

  /* System messages — centered, muted */
  .msg-system {
    padding: var(--sp-xs) 0;
    text-align: center;
  }

  .system-text {
    font-size: 0.75rem;
    color: var(--text-tertiary);
    font-style: italic;
  }

  /* ── Markdown styles ─────────────────────────────────────── */

  .markdown :global(p) {
    margin-bottom: 0.5em;
  }
  .markdown :global(p:last-child) {
    margin-bottom: 0;
  }

  .markdown :global(h1),
  .markdown :global(h2),
  .markdown :global(h3),
  .markdown :global(h4) {
    margin: 0.75em 0 0.35em;
    font-weight: 700;
    color: var(--text-primary);
  }
  .markdown :global(h1) { font-size: 1.1rem; }
  .markdown :global(h2) { font-size: 1rem; }
  .markdown :global(h3) { font-size: 0.95rem; }
  .markdown :global(h4) { font-size: 0.9rem; }

  .markdown :global(.code-block-wrap) {
    margin: 0.5em 0;
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    overflow: hidden;
  }

  .markdown :global(.code-header) {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 2px var(--sp-sm);
    background: #0f0f1e;
    border-bottom: 1px solid var(--border);
    font-family: var(--font-mono);
    font-size: 0.7rem;
  }

  .markdown :global(.code-lang) {
    color: var(--text-tertiary);
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .markdown :global(.code-copy-btn) {
    background: none;
    border: 1px solid var(--border);
    border-radius: 3px;
    color: var(--text-tertiary);
    font-family: var(--font-mono);
    font-size: 0.65rem;
    padding: 1px 6px;
    cursor: pointer;
    transition: all 0.15s;
  }
  .markdown :global(.code-copy-btn:hover) {
    color: var(--accent);
    border-color: var(--accent);
  }

  .markdown :global(.code-block-wrap pre) {
    background: #0d0d18;
    padding: var(--sp-sm);
    margin: 0;
    overflow-x: auto;
    -webkit-overflow-scrolling: touch;
    border: none;
    border-radius: 0;
  }

  .markdown :global(pre) {
    background: #0d0d18;
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    padding: var(--sp-sm);
    margin: 0.5em 0;
    overflow-x: auto;
    -webkit-overflow-scrolling: touch;
  }

  .markdown :global(code) {
    font-family: var(--font-mono);
    font-size: 0.8rem;
    line-height: 1.5;
  }

  .markdown :global(:not(pre) > code) {
    background: #1a1a2e;
    padding: 1px 4px;
    border-radius: 3px;
    font-size: 0.85em;
  }

  .markdown :global(a) {
    color: var(--accent);
    text-decoration: none;
  }
  .markdown :global(a:hover) {
    text-decoration: underline;
  }

  .markdown :global(ul),
  .markdown :global(ol) {
    padding-left: 1.5em;
    margin: 0.35em 0;
  }

  .markdown :global(li) {
    margin: 0.15em 0;
  }

  .markdown :global(blockquote) {
    border-left: 3px solid var(--accent);
    padding-left: var(--sp-md);
    margin: 0.5em 0;
    color: var(--text-secondary);
  }

  .markdown :global(hr) {
    border: none;
    border-top: 1px solid var(--border);
    margin: 0.75em 0;
  }

  .markdown :global(table) {
    width: 100%;
    border-collapse: collapse;
    margin: 0.5em 0;
    font-size: 0.8rem;
  }

  .markdown :global(th),
  .markdown :global(td) {
    border: 1px solid var(--border);
    padding: 2px var(--sp-sm);
    text-align: left;
  }

  .markdown :global(th) {
    background: var(--surface-hover);
    font-weight: 600;
  }

  .markdown :global(strong) {
    font-weight: 700;
    color: var(--text-primary);
  }

  .markdown :global(em) {
    font-style: italic;
  }

  /* ── Syntax highlighting (dark theme) ────────────────────── */

  .markdown :global(.hljs-keyword),
  .markdown :global(.hljs-selector-tag) {
    color: #c792ea;
  }

  .markdown :global(.hljs-string),
  .markdown :global(.hljs-addition) {
    color: #c3e88d;
  }

  .markdown :global(.hljs-number),
  .markdown :global(.hljs-literal) {
    color: #f78c6c;
  }

  .markdown :global(.hljs-comment),
  .markdown :global(.hljs-quote) {
    color: #546e7a;
    font-style: italic;
  }

  .markdown :global(.hljs-title),
  .markdown :global(.hljs-section) {
    color: #82aaff;
  }

  .markdown :global(.hljs-built_in),
  .markdown :global(.hljs-type) {
    color: #ffcb6b;
  }

  .markdown :global(.hljs-attr),
  .markdown :global(.hljs-name),
  .markdown :global(.hljs-selector-class) {
    color: var(--accent);
  }

  .markdown :global(.hljs-deletion) {
    color: #f07178;
  }

  .markdown :global(.hljs-variable),
  .markdown :global(.hljs-template-variable) {
    color: #eeffff;
  }

  .markdown :global(.hljs-meta) {
    color: #89ddff;
  }
</style>
