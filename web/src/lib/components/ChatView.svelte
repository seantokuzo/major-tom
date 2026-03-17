<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import MessageBubble from './MessageBubble.svelte';
  import ApprovalCard from './ApprovalCard.svelte';
  import type { ApprovalDecision } from '../protocol/messages';

  let messagesEnd: HTMLDivElement | undefined;

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

  function handleApproval(id: string, decision: ApprovalDecision) {
    relay.sendApproval(id, decision);
  }

  // Auto-scroll on new messages
  $effect(() => {
    relay.messages.length;
    // Tick before scroll so DOM updates first
    queueMicrotask(scrollToBottom);
  });
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
    <div bind:this={messagesEnd}></div>
  </div>

  <!-- Input bar -->
  <form class="input-bar" onsubmit={handleSubmit}>
    <textarea
      class="input-field"
      bind:value={relay.inputText}
      onkeydown={handleKeydown}
      placeholder="Send a prompt..."
      rows="1"
      disabled={!relay.hasSession}
    ></textarea>
    <button
      class="send-btn"
      type="submit"
      disabled={!relay.inputText.trim() || !relay.hasSession}
    >
      ↑
    </button>
  </form>
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
    padding: var(--sp-md);
    display: flex;
    flex-direction: column;
    gap: var(--sp-sm);
  }

  .input-bar {
    display: flex;
    align-items: flex-end;
    gap: var(--sp-md);
    padding: var(--sp-md);
    background: var(--surface);
    border-top: 1px solid var(--border);
    flex-shrink: 0;
  }

  .input-field {
    flex: 1;
    background: transparent;
    border: none;
    outline: none;
    color: var(--text-primary);
    font-family: var(--font-body);
    font-size: 0.95rem;
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
    width: 36px;
    height: 36px;
    border-radius: var(--r-full);
    border: none;
    background: var(--accent);
    color: #000;
    font-size: 1.1rem;
    font-weight: 700;
    cursor: pointer;
    transition: opacity 0.15s;
    flex-shrink: 0;
  }
  .send-btn:hover { opacity: 0.85; }
  .send-btn:disabled {
    background: var(--text-tertiary);
    cursor: default;
    opacity: 0.4;
  }
</style>
