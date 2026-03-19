<script lang="ts">
  import type { ChatMessage } from '../stores/relay.svelte';
  import { renderMarkdown } from '../utils/markdown';

  let { message }: { message: ChatMessage } = $props();

  const roleStyles: Record<string, string> = {
    user: 'bubble-user',
    assistant: 'bubble-assistant',
    tool: 'bubble-tool',
    system: 'bubble-system',
  };

  const roleLabels: Record<string, string> = {
    user: 'You',
    assistant: 'Claude',
    tool: 'Tool',
    system: 'System',
  };

  let rendered = $derived(
    message.role === 'assistant' ? renderMarkdown(message.content) : ''
  );
</script>

<div class="bubble {roleStyles[message.role]}">
  <span class="role-label">{roleLabels[message.role]}</span>
  {#if message.role === 'assistant'}
    <div class="content markdown">{@html rendered}</div>
  {:else}
    <div class="content">{message.content}</div>
  {/if}
</div>

<style>
  .bubble {
    padding: var(--sp-md) var(--sp-lg);
    border-radius: var(--r-md);
    max-width: 85%;
    word-wrap: break-word;
  }

  .role-label {
    display: block;
    font-size: 0.7rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    margin-bottom: var(--sp-xs);
  }

  .content {
    font-size: 0.9rem;
    line-height: 1.5;
    white-space: pre-wrap;
  }

  .bubble-user {
    background: var(--accent-dim);
    align-self: flex-end;
    margin-left: auto;
  }
  .bubble-user .role-label { color: rgba(255,255,255,0.6); }

  .bubble-assistant {
    background: var(--surface);
    border: 1px solid var(--border);
    align-self: flex-start;
  }
  .bubble-assistant .role-label { color: var(--accent); }

  .bubble-tool {
    background: transparent;
    align-self: flex-start;
    padding: var(--sp-xs) var(--sp-lg);
  }
  .bubble-tool .role-label { display: none; }
  .bubble-tool .content {
    font-size: 0.8rem;
    color: var(--text-tertiary);
    font-family: var(--font-mono);
  }

  .bubble-system {
    background: transparent;
    align-self: center;
    text-align: center;
  }
  .bubble-system .role-label { display: none; }
  .bubble-system .content {
    font-size: 0.8rem;
    color: var(--deny);
  }

  /* ── Markdown styles ─────────────────────────────────────── */

  .markdown {
    white-space: normal;
  }

  .markdown :global(p) {
    margin-bottom: 0.75em;
  }
  .markdown :global(p:last-child) {
    margin-bottom: 0;
  }

  .markdown :global(h1),
  .markdown :global(h2),
  .markdown :global(h3),
  .markdown :global(h4) {
    margin: 1em 0 0.5em;
    font-weight: 700;
    color: var(--text-primary);
  }
  .markdown :global(h1) { font-size: 1.3rem; }
  .markdown :global(h2) { font-size: 1.15rem; }
  .markdown :global(h3) { font-size: 1.05rem; }
  .markdown :global(h4) { font-size: 0.95rem; }

  .markdown :global(pre) {
    background: #0d0d18;
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    padding: var(--sp-md);
    margin: 0.75em 0;
    overflow-x: auto;
    -webkit-overflow-scrolling: touch;
  }

  .markdown :global(code) {
    font-family: var(--font-mono);
    font-size: 0.82rem;
    line-height: 1.6;
  }

  .markdown :global(:not(pre) > code) {
    background: #1a1a2e;
    padding: 2px 6px;
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
    margin: 0.5em 0;
  }

  .markdown :global(li) {
    margin: 0.25em 0;
  }

  .markdown :global(blockquote) {
    border-left: 3px solid var(--accent);
    padding-left: var(--sp-md);
    margin: 0.75em 0;
    color: var(--text-secondary);
  }

  .markdown :global(hr) {
    border: none;
    border-top: 1px solid var(--border);
    margin: 1em 0;
  }

  .markdown :global(table) {
    width: 100%;
    border-collapse: collapse;
    margin: 0.75em 0;
    font-size: 0.85rem;
  }

  .markdown :global(th),
  .markdown :global(td) {
    border: 1px solid var(--border);
    padding: var(--sp-xs) var(--sp-sm);
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
