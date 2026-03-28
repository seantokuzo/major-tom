<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import { promptHistory } from '../stores/prompt-history.svelte';
  import MessageBubble from './MessageBubble.svelte';
  import ApprovalCard from './ApprovalCard.svelte';
  import CommandPalette from './CommandPalette.svelte';
  import PromptHistoryOverlay from './PromptHistoryOverlay.svelte';
  import SessionDrawer from './SessionDrawer.svelte';
  import { sessionStateManager } from '../stores/session-state.svelte';
  import DeviceList from './DeviceList.svelte';
  import StreamingIndicator from './StreamingIndicator.svelte';
  import ToolFeed from './ToolFeed.svelte';
  import VoiceMicButton from './VoiceMicButton.svelte';
  import TemplateDrawer from './TemplateDrawer.svelte';
  import TemplateSaveDialog from './TemplateSaveDialog.svelte';
  import FileTreeBrowser from './FileTreeBrowser.svelte';
  import ContextChips from './ContextChips.svelte';
  import CountdownToast from './CountdownToast.svelte';
  import type { ApprovalDecision } from '../protocol/messages';

  let messagesEnd: HTMLDivElement | undefined;
  let messagesContainer: HTMLDivElement | undefined;
  let inputEl: HTMLTextAreaElement | undefined;
  let paletteOpen = $state(false);
  let templateDrawerOpen = $state(false);
  let templateSaveOpen = $state(false);
  let saveDialogContent = $state('');
  let historyOpen = $state(false);
  let devicesOpen = $state(false);
  let fileTreeOpen = $state(false);
  let countdownToastRef: CountdownToast | undefined;

  // ── Smart auto-scroll ──────────────────────────────────────
  let isNearBottom = $state(true);
  let showScrollBtn = $derived(!isNearBottom);

  function checkScrollPosition() {
    if (!messagesContainer) return;
    const { scrollTop, scrollHeight, clientHeight } = messagesContainer;
    // "Near bottom" = within 150px of the bottom
    isNearBottom = scrollHeight - scrollTop - clientHeight < 150;
  }

  function scrollToBottom() {
    messagesEnd?.scrollIntoView({ behavior: 'smooth' });
    isNearBottom = true;
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

  function openFileTree() {
    fileTreeOpen = true;
  }

  function handleFileTreeClose() {
    fileTreeOpen = false;
    queueMicrotask(() => inputEl?.focus());
  }

  function handleApproval(id: string, decision: ApprovalDecision) {
    relay.sendApproval(id, decision);
  }

  // Shared clock for relative timestamps — single timer instead of per-message
  let sharedNow = $state(Date.now());
  $effect(() => {
    const id = setInterval(() => { sharedNow = Date.now(); }, 15_000);
    return () => clearInterval(id);
  });

  // Auto-scroll on new messages — only if user is near the bottom
  $effect(() => {
    relay.messages.length;
    if (isNearBottom) queueMicrotask(scrollToBottom);
  });

  // Persist messages to IndexedDB (debounced to avoid jank during streaming)
  let persistTimer: ReturnType<typeof setTimeout> | undefined;
  $effect(() => {
    relay.messages.length;
    // Access deep content to track mutations
    relay.messages.forEach((m) => m.content);
    clearTimeout(persistTimer);
    persistTimer = setTimeout(() => relay.persistMessages(), 500);
    return () => clearTimeout(persistTimer);
  });

  // Window-level Escape listener to close devices modal (fires even when focus is in textarea)
  $effect(() => {
    if (!devicesOpen) return;
    function onKeydown(e: KeyboardEvent) {
      if (e.key === 'Escape') {
        devicesOpen = false;
      }
    }
    window.addEventListener('keydown', onKeydown);
    return () => window.removeEventListener('keydown', onKeydown);
  });

  // Filter approvals — in delay mode, hide approvals with active countdown toasts
  let visibleApprovals = $derived.by(() => {
    const countdownIds = countdownToastRef?.getCountdownIds() ?? new Set<string>();
    return relay.pendingApprovals.filter(a => !countdownIds.has(a.id));
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
  <!-- Countdown toasts (delay mode) -->
  <CountdownToast bind:this={countdownToastRef} />

  <!-- Approvals bar — in delay mode, only show approvals that were cancelled from countdown -->
  {#if visibleApprovals.length > 0}
    <div class="approvals-bar">
      {#each visibleApprovals as request (request.id)}
        <ApprovalCard {request} onDecision={handleApproval} />
      {/each}
    </div>
  {/if}

  <!-- Messages -->
  <div class="messages" bind:this={messagesContainer} onscroll={checkScrollPosition}>
    {#each relay.messages as message, i (message.id)}
      {#if message.role === 'user' && i > 0}
        <div class="turn-separator" role="separator"></div>
      {/if}
      <MessageBubble {message} now={sharedNow} />
    {/each}
    <StreamingIndicator />
    <div bind:this={messagesEnd}></div>
  </div>

  <!-- Scroll-to-bottom FAB -->
  {#if showScrollBtn}
    <button class="scroll-bottom-btn" onclick={scrollToBottom} aria-label="Scroll to bottom" title="Scroll to bottom">&darr;</button>
  {/if}

  <!-- Tool activity feed -->
  <ToolFeed />

  <!-- Context chips -->
  <ContextChips />

  <!-- Input bar -->
  <form class="input-bar" class:input-bar-disabled={inputDisabled} onsubmit={handleSubmit}>
    <span class="input-prompt">&gt;</span>
    <button
      class="file-btn"
      type="button"
      aria-label="Attach files"
      onclick={openFileTree}
      disabled={inputDisabled}
      title="Browse workspace files"
    >
      &#x1F4C4;
    </button>
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
    onOpenSessions={() => { sessionStateManager.togglePanel(); }}
    onOpenDevices={() => { devicesOpen = true; }}
    onOpenFiles={openFileTree}
  />
  <TemplateDrawer bind:open={templateDrawerOpen} onClose={handleTemplateDrawerClose} />
  <TemplateSaveDialog bind:open={templateSaveOpen} onClose={handleTemplateSaveClose} initialContent={saveDialogContent} />
  <PromptHistoryOverlay bind:open={historyOpen} onClose={handleHistoryClose} onSelectEntry={handleHistorySelect} />
  {#if devicesOpen}
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="modal-backdrop" onclick={() => { devicesOpen = false; }} role="presentation">
      <div class="modal-content" onclick={(e) => e.stopPropagation()} role="dialog" aria-label="Device management" aria-modal="true">
        <button class="modal-close" onclick={() => { devicesOpen = false; }} aria-label="Close" autofocus>&times;</button>
        <DeviceList />
      </div>
    </div>
  {/if}
  <FileTreeBrowser bind:open={fileTreeOpen} onClose={handleFileTreeClose} />
</div>

<style>
  .chat-view {
    flex: 1;
    display: flex;
    flex-direction: column;
    min-height: 0;
    position: relative;
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

  .turn-separator {
    height: 1px;
    background: var(--border);
    margin: var(--sp-sm) 0;
    opacity: 0.5;
  }

  .scroll-bottom-btn {
    position: absolute;
    bottom: 80px;
    right: var(--sp-md);
    width: 36px;
    height: 36px;
    border-radius: var(--r-full);
    border: 1px solid var(--border);
    background: var(--surface);
    color: var(--accent);
    font-size: 1rem;
    font-weight: 700;
    cursor: pointer;
    z-index: 10;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.4);
    transition: all 0.15s;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .scroll-bottom-btn:hover {
    background: var(--accent);
    color: #000;
    border-color: var(--accent);
  }

  .input-bar {
    display: flex;
    align-items: flex-end;
    gap: var(--sp-xs);
    padding: var(--sp-sm) var(--sp-sm);
    padding-bottom: max(var(--sp-sm), env(safe-area-inset-bottom));
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
    min-width: 0;
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
    width: 36px;
    height: 36px;
    border-radius: var(--r-sm);
    border: 1px solid var(--border);
    background: transparent;
    color: var(--text-tertiary);
    font-size: 0.85rem;
    cursor: pointer;
    transition: all 0.15s;
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: center;
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
    width: 36px;
    height: 36px;
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

  .file-btn {
    width: 36px;
    height: 36px;
    border-radius: var(--r-sm);
    border: 1px solid var(--border);
    background: transparent;
    font-size: 0.85rem;
    cursor: pointer;
    transition: all 0.15s;
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
  }
  .file-btn:hover:not(:disabled) {
    border-color: var(--accent);
  }
  .file-btn:disabled {
    opacity: 0.4;
    cursor: default;
  }

  .send-btn {
    width: 36px;
    height: 36px;
    border-radius: var(--r-sm);
    border: 1px solid var(--border);
    background: transparent;
    color: var(--accent);
    font-size: 1rem;
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

  .modal-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 100;
  }

  .modal-content {
    position: relative;
    background: var(--bg);
    border: 1px solid var(--border);
    border-radius: var(--r-md);
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5);
    max-height: 80vh;
    overflow-y: auto;
    width: 90%;
    max-width: 500px;
  }

  .modal-close {
    position: absolute;
    top: var(--sp-sm);
    right: var(--sp-sm);
    background: none;
    border: none;
    color: var(--text-tertiary);
    font-size: 1.3rem;
    cursor: pointer;
    padding: 2px 6px;
    line-height: 1;
    z-index: 1;
  }
  .modal-close:hover {
    color: var(--text-primary);
  }
</style>
