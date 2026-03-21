<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import { promptHistory } from '../stores/prompt-history.svelte';
  import MessageBubble from './MessageBubble.svelte';
  import ApprovalCard from './ApprovalCard.svelte';
  import CommandPalette from './CommandPalette.svelte';
  import PromptHistoryOverlay from './PromptHistoryOverlay.svelte';
  import SessionDrawer from './SessionDrawer.svelte';
  import StreamingIndicator from './StreamingIndicator.svelte';
  import ToolFeed from './ToolFeed.svelte';
  import VoiceMicButton from './VoiceMicButton.svelte';
  import TemplateDrawer from './TemplateDrawer.svelte';
  import TemplateSaveDialog from './TemplateSaveDialog.svelte';
  import type { ApprovalDecision } from '../protocol/messages';

  let messagesEnd: HTMLDivElement | undefined;
  let inputEl: HTMLTextAreaElement | undefined;
  let paletteOpen = $state(false);
  let templateDrawerOpen = $state(false);
  let templateSaveOpen = $state(false);
  let saveDialogContent = $state('');
  let historyOpen = $state(false);
  let sessionDrawerOpen = $state(false);

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
      return;
    }

    // Arrow-up: cycle through prompt history
    if (e.key === 'ArrowUp' && (relay.inputText.trim() === '' || promptHistory.isNavigating)) {
      e.preventDefault();
      const result = promptHistory.navigate('up', relay.inputText);
      if (result !== null) relay.inputText = result;
      return;
    }

    // Arrow-down: cycle back through history
    if (e.key === 'ArrowDown' && promptHistory.isNavigating) {
      e.preventDefault();
      const result = promptHistory.navigate('down', relay.inputText);
      if (result !== null) relay.inputText = result;
      return;
    }
  }

  function handleInput() {
    // Reset history navigation when user types
    promptHistory.resetNavigation();

    // Open command palette when / is typed as first character
    if (relay.inputText === '/') {
      relay.inputText = '';
      paletteOpen = true;
    }
  }

  function handleHistoryClose() {
    historyOpen = false;
    promptHistory.resetNavigation();
    queueMicrotask(() => inputEl?.focus());
  }

  function handleHistorySelect(text: string) {
    relay.inputText = text;
    promptHistory.resetNavigation();
    queueMicrotask(() => inputEl?.focus());
  }

  function handlePaletteClose() {
    paletteOpen = false;
    if (!templateDrawerOpen && !templateSaveOpen) {
      queueMicrotask(() => inputEl?.focus());
    }
  }

  function handleOpenTemplates() {
    paletteOpen = false;
    templateDrawerOpen = true;
  }

  function handleOpenSaveTemplate() {
    paletteOpen = false;
    saveDialogContent = relay.inputText;
    templateSaveOpen = true;
  }

  function handleTemplateDrawerClose() {
    templateDrawerOpen = false;
    queueMicrotask(() => inputEl?.focus());
  }

  function handleTemplateSaveClose() {
    templateSaveOpen = false;
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
    return () => clearTimeout(persistTimer);
  });

  /** Disable input when not connected or reconnecting */
  let inputDisabled = $derived(!relay.hasSession || !relay.isConnected);

  let placeholderText = $derived.by(() => {
    if (relay.isReconnecting) return 'Reconnecting to relay...';
    if (relay.isDisconnected) return relay.connectionError ?? 'Disconnected';
    if (relay.inputPrefix) return `${relay.inputPrefix}...`;
    if (relay.hasSession) return 'Send a prompt...';
    return 'Connect and start a session';
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
    <StreamingIndicator />
    <div bind:this={messagesEnd}></div>
  </div>

  <!-- Tool activity feed -->
  <ToolFeed />

  <!-- Input bar -->
  <form class="input-bar" class:input-bar-disabled={inputDisabled} onsubmit={handleSubmit}>
    <span class="input-prompt">&gt;</span>
    <textarea
      bind:this={inputEl}
      class="input-field"
      bind:value={relay.inputText}
      onkeydown={handleKeydown}
      oninput={handleInput}
      placeholder={placeholderText}
      rows="1"
      disabled={inputDisabled}
    ></textarea>
    <VoiceMicButton relay={relay} disabled={inputDisabled} />
    <button
      class="template-btn"
      type="button"
      aria-label="Templates"
      onclick={() => templateDrawerOpen = true}
      disabled={inputDisabled}
    >
      &#9733;
    </button>
    <button
      class="history-btn"
      type="button"
      aria-label="Prompt history"
      onclick={() => { promptHistory.resetNavigation(); historyOpen = true; }}
      disabled={inputDisabled}
      title="Prompt history"
    >
      &#x29D6;
    </button>
    <button
      class="send-btn"
      type="submit"
      aria-label="Send message"
      disabled={!relay.inputText.trim() || inputDisabled}
    >
      &uarr;
    </button>
  </form>

  <CommandPalette
    bind:open={paletteOpen}
    onClose={handlePaletteClose}
    onOpenTemplates={handleOpenTemplates}
    onOpenSaveTemplate={handleOpenSaveTemplate}
    onOpenSessions={() => { sessionDrawerOpen = true; }}
  />
  <TemplateDrawer bind:open={templateDrawerOpen} onClose={handleTemplateDrawerClose} />
  <TemplateSaveDialog bind:open={templateSaveOpen} onClose={handleTemplateSaveClose} initialContent={saveDialogContent} />
  <PromptHistoryOverlay bind:open={historyOpen} onClose={handleHistoryClose} onSelectEntry={handleHistorySelect} />
  <SessionDrawer bind:open={sessionDrawerOpen} onclose={() => { sessionDrawerOpen = false; }} />
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
    transition: opacity 0.2s;
  }

  .input-bar-disabled {
    opacity: 0.6;
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

  .template-btn {
    width: 28px;
    height: 28px;
    border-radius: var(--r-sm);
    border: 1px solid var(--border);
    background: transparent;
    color: var(--text-tertiary);
    font-size: 0.8rem;
    cursor: pointer;
    transition: all 0.15s;
    flex-shrink: 0;
  }
  .template-btn:hover:not(:disabled) {
    color: var(--accent);
    border-color: var(--accent);
  }
  .template-btn:disabled {
    opacity: 0.4;
    cursor: default;
  }

  .history-btn {
    width: 28px;
    height: 28px;
    border-radius: var(--r-sm);
    border: 1px solid var(--border);
    background: transparent;
    color: var(--text-secondary);
    font-size: 0.85rem;
    cursor: pointer;
    transition: all 0.15s;
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .history-btn:hover:not(:disabled) {
    color: var(--accent);
    border-color: var(--accent);
  }
  .history-btn:disabled {
    color: var(--text-tertiary);
    border-color: var(--border);
    cursor: default;
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
