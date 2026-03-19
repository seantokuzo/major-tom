<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import MessageBubble from './MessageBubble.svelte';
  import ApprovalCard from './ApprovalCard.svelte';
  import CommandPalette from './CommandPalette.svelte';
  import StreamingIndicator from './StreamingIndicator.svelte';
  import type { ApprovalDecision } from '../protocol/messages';

  let messagesEnd: HTMLDivElement | undefined;
  let inputEl: HTMLTextAreaElement | undefined;
  let paletteOpen = $state(false);

  function scrollToBottom() {
    messagesEnd?.scrollIntoView({ behavior: 'smooth' });
  }

  function handleSubmit(e: Event) {
    e.preventDefault();
    relay.sendPrompt();
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      relay.sendPrompt();
    }
  }

  function handleInput() {
    // Open command palette when / is typed as first character
    if (relay.inputText === '/') {
      relay.inputText = '';
      paletteOpen = true;
    }
  }

  function handlePaletteClose() {
    paletteOpen = false;
    queueMicrotask(() => inputEl?.focus());
  }

  function handleApproval(id: string, decision: ApprovalDecision) {
    relay.sendApproval(id, decision);
  }

  // Auto-scroll on new messages
  $effect(() => {
    relay.messages.length;
    queueMicrotask(scrollToBottom);
  });

  // Persist messages to localStorage (debounced to avoid jank during streaming)
  let persistTimer: ReturnType<typeof setTimeout> | undefined;
  $effect(() => {
    relay.messages.length;
    // Access deep content to track mutations
    relay.messages.forEach((m) => m.content);
    clearTimeout(persistTimer);
    persistTimer = setTimeout(() => relay.persistMessages(), 500);
  });

  let placeholderText = $derived(
    relay.inputPrefix
      ? `${relay.inputPrefix}...`
      : relay.hasSession
        ? 'Send a prompt...'
        : 'Connect and start a session'
  );
</script>

<div class="chat-view">
  <!-- Approvals bar -->
  {#if relay.pendingApprovals.length > 0}
    <div class="approvals-bar">
      {#each relay.pendingApprovals as request (request.id)}
        <ApprovalCard {request} onDecision={handleApproval} />
      {/each}
    </div>
  {/if}

  <!-- Messages -->
  <div class="messages">
    {#each relay.messages as message (message.id)}
      <MessageBubble {message} />
    {/each}
    <StreamingIndicator />
    <div bind:this={messagesEnd}></div>
  </div>

  <!-- Input bar -->
  <form class="input-bar" onsubmit={handleSubmit}>
    <span class="input-prompt">&gt;</span>
    <textarea
      bind:this={inputEl}
      class="input-field"
      bind:value={relay.inputText}
      onkeydown={handleKeydown}
      oninput={handleInput}
      placeholder={placeholderText}
      rows="1"
      disabled={!relay.hasSession}
    ></textarea>
    <button
      class="send-btn"
      type="submit"
      aria-label="Send message"
      disabled={!relay.inputText.trim() || !relay.hasSession}
    >
      &uarr;
    </button>
  </form>

  <CommandPalette bind:open={paletteOpen} onClose={handlePaletteClose} />
</div>

<style>
  .chat-view {
    flex: 1;
    display: flex;
    flex-direction: column;
    min-height: 0;
  }

  .approvals-bar {
    display: flex;
    gap: var(--sp-md);
    padding: var(--sp-md);
    overflow-x: auto;
    background: rgba(20, 20, 31, 0.7);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
  }

  .messages {
    flex: 1;
    overflow-y: auto;
    padding: var(--sp-sm) var(--sp-md);
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .input-bar {
    display: flex;
    align-items: flex-end;
    gap: var(--sp-sm);
    padding: var(--sp-sm) var(--sp-md);
    background: var(--surface);
    border-top: 1px solid var(--border);
    flex-shrink: 0;
  }

  .input-prompt {
    font-family: var(--font-mono);
    font-size: 0.9rem;
    color: var(--accent);
    line-height: 1.5;
    padding-bottom: 2px;
    flex-shrink: 0;
    user-select: none;
  }

  .input-field {
    flex: 1;
    background: transparent;
    border: none;
    outline: none;
    color: var(--text-primary);
    font-family: var(--font-mono);
    font-size: 0.9rem;
    resize: none;
    line-height: 1.5;
    max-height: 120px;
  }
  .input-field::placeholder {
    color: var(--text-tertiary);
  }
  .input-field:disabled {
    opacity: 0.4;
  }

  .send-btn {
    width: 28px;
    height: 28px;
    border-radius: var(--r-sm);
    border: 1px solid var(--border);
    background: transparent;
    color: var(--accent);
    font-size: 0.9rem;
    font-weight: 700;
    cursor: pointer;
    transition: all 0.15s;
    flex-shrink: 0;
  }
  .send-btn:hover:not(:disabled) {
    background: var(--accent);
    color: #000;
  }
  .send-btn:disabled {
    color: var(--text-tertiary);
    border-color: var(--border);
    cursor: default;
    opacity: 0.4;
  }
</style>
