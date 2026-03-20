<script lang="ts">
  import type { ChatMessage } from '../stores/relay.svelte';
  import { renderMarkdown } from '../utils/markdown';
  import DiffViewer from './DiffViewer.svelte';

  let { message }: { message: ChatMessage } = $props();

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
  {:else if message.role === 'assistant'}
    <div class="assistant-text markdown">{@html rendered}</div>
  {:else if message.role === 'tool'}
    {#if diffData}
      <DiffViewer
        filePath={diffData.filePath}
        oldContent={diffData.oldContent}
        newContent={diffData.newContent}
      />
    {:else}
      <span class="tool-text">{message.content}</span>
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

  /* Tool messages — subtle inline status */
  .msg-tool {
    padding: 1px 0;
  }

  .tool-text {
    font-size: 0.75rem;
    color: var(--text-tertiary);
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
