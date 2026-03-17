<script lang="ts">
  import type { ChatMessage } from '../stores/relay.svelte';

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
</script>

<div class="bubble {roleStyles[message.role]}">
  <span class="role-label">{roleLabels[message.role]}</span>
  <div class="content">{message.content}</div>
</div>

<style>
  .bubble {
    padding: var(--sp-md) var(--sp-lg);
    border-radius: var(--r-md);
    max-width: 85%;
    word-wrap: break-word;
    white-space: pre-wrap;
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
  .bubble-assistant .content { font-family: var(--font-mono); font-size: 0.85rem; }

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
</style>
