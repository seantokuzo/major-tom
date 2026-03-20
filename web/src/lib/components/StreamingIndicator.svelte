<script lang="ts">
  import { relay } from '../stores/relay.svelte';

  const toolIcons: Record<string, string> = {
    Bash: '$ _',
    Read: '>>',
    Write: '<<',
    Edit: '~=',
    Grep: '??',
    Glob: '**',
    WebFetch: '{}',
    WebSearch: '??',
    TodoRead: '[]',
    TodoWrite: '[x]',
  };

  let toolIcon = $derived(
    relay.activeToolName
      ? toolIcons[relay.activeToolName] ?? '>>'
      : null
  );
</script>

{#if relay.isWaitingForResponse || relay.activeToolName}
  <div class="indicator">
    {#if relay.activeToolName}
      <span class="tool-indicator">
        <span class="tool-icon">{toolIcon}</span>
        <span class="tool-spinner"></span>
        <span class="tool-label">Using {relay.activeToolName}...</span>
      </span>
    {:else}
      <span class="thinking">
        <span class="brain">*</span>
        <span class="dot"></span>
        <span class="dot"></span>
        <span class="dot"></span>
        <span class="thinking-label">Thinking</span>
      </span>
    {/if}
  </div>
{/if}

<style>
  .indicator {
    padding: var(--sp-xs) var(--sp-lg);
    font-family: var(--font-mono);
    font-size: 0.8rem;
    color: var(--text-tertiary);
  }

  /* ── Thinking state ────────────────────────────────── */

  .thinking {
    display: inline-flex;
    align-items: center;
    gap: 2px;
  }

  .brain {
    color: var(--accent);
    font-size: 0.9rem;
    margin-right: var(--sp-xs);
    animation: brain-pulse 2s ease-in-out infinite;
  }

  @keyframes brain-pulse {
    0%, 100% { opacity: 0.5; transform: scale(1); }
    50% { opacity: 1; transform: scale(1.15); }
  }

  .dot {
    display: inline-block;
    width: 4px;
    height: 4px;
    border-radius: 50%;
    background: var(--accent);
    animation: dot-bounce 1.4s ease-in-out infinite;
    margin-right: 1px;
  }
  .dot:nth-child(3) { animation-delay: 0.2s; }
  .dot:nth-child(4) { animation-delay: 0.4s; }

  @keyframes dot-bounce {
    0%, 80%, 100% { opacity: 0.3; transform: scale(0.8); }
    40% { opacity: 1; transform: scale(1.2); }
  }

  .thinking-label {
    margin-left: var(--sp-xs);
    color: var(--text-tertiary);
    animation: fade-in-out 2s ease-in-out infinite;
  }

  @keyframes fade-in-out {
    0%, 100% { opacity: 0.5; }
    50% { opacity: 1; }
  }

  /* ── Tool state ────────────────────────────────────── */

  .tool-indicator {
    display: inline-flex;
    align-items: center;
    gap: var(--sp-sm);
    color: var(--text-secondary);
  }

  .tool-icon {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    font-weight: 700;
    color: var(--accent);
    background: rgba(212, 168, 83, 0.1);
    padding: 1px 4px;
    border-radius: 2px;
    letter-spacing: -0.02em;
  }

  .tool-spinner {
    display: inline-block;
    width: 10px;
    height: 10px;
    border: 2px solid var(--border);
    border-top-color: var(--accent);
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  .tool-label {
    color: var(--text-secondary);
    font-size: 0.8rem;
  }
</style>
