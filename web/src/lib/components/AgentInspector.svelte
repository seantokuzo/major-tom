<script lang="ts">
  import { onDestroy } from 'svelte';
  import type { OfficeAgent } from '../office/types';
  import { getCharacterConfig } from '../office/characters';
  import { STATUS_COLORS } from '../office/state.svelte';
  import { relay } from '../stores/relay.svelte';

  interface Props {
    agent: OfficeAgent;
    onRename?: (newName: string) => void;
    onClose?: () => void;
  }

  let { agent, onRename, onClose }: Props = $props();

  let isRenaming = $state(false);
  let renameText = $state('');
  let messageText = $state('');
  let now = $state(Date.now());

  // Tick every second so uptime updates reactively
  const uptimeInterval = setInterval(() => { now = Date.now(); }, 1000);
  onDestroy(() => clearInterval(uptimeInterval));

  const config = $derived(getCharacterConfig(agent.characterType));

  const statusColor = $derived(STATUS_COLORS[agent.status] ?? STATUS_COLORS.spawning);

  const uptime = $derived.by(() => {
    const ms = now - agent.spawnedAt.getTime();
    const totalSeconds = Math.floor(ms / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    if (minutes > 0) return `${minutes}m ${seconds}s`;
    return `${seconds}s`;
  });

  const truncatedId = $derived(agent.id.slice(0, 12) + '...');
  const deskLabel = $derived(agent.deskIndex !== null ? `Desk ${agent.deskIndex + 1}` : 'None');

  const isTerminal = $derived(agent.status === 'complete' || agent.status === 'dismissed');

  function sendMessage() {
    if (!messageText.trim() || isTerminal) return;
    relay.sendAgentMessage(agent.id, messageText.trim());
    messageText = '';
  }

  function handleMessageKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      sendMessage();
    }
  }

  function startRename() {
    renameText = agent.name;
    isRenaming = true;
  }

  function submitRename() {
    if (renameText.trim()) {
      onRename?.(renameText.trim());
    }
    isRenaming = false;
  }

  function cancelRename() {
    isRenaming = false;
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter') submitRename();
    if (e.key === 'Escape') cancelRename();
  }
</script>

<aside class="inspector">
  <!-- Header -->
  <div class="header">
    <div class="header-left">
      <div class="color-dot" style="background: {config.spriteColor}"></div>
      <div class="header-info">
        {#if isRenaming}
          <input
            class="rename-input"
            type="text"
            bind:value={renameText}
            onkeydown={handleKeydown}
            autofocus
          />
        {:else}
          <span class="agent-name">{agent.name}</span>
        {/if}
        <span class="agent-type">{config.displayName}</span>
      </div>
    </div>
    <span class="status-badge" style="color: {statusColor}; background: {statusColor}22;">
      {agent.status.toUpperCase()}
    </span>
  </div>

  <div class="divider"></div>

  <!-- Detail rows -->
  <div class="details">
    <div class="detail-row">
      <span class="detail-label">Role</span>
      <span class="detail-value">{agent.role}</span>
    </div>
    <div class="detail-row">
      <span class="detail-label">Agent ID</span>
      <span class="detail-value">{truncatedId}</span>
    </div>
    <div class="detail-row">
      <span class="detail-label">Desk</span>
      <span class="detail-value">{deskLabel}</span>
    </div>
    <div class="detail-row">
      <span class="detail-label">Uptime</span>
      <span class="detail-value">{uptime}</span>
    </div>
  </div>

  <!-- Current task -->
  {#if agent.currentTask}
    <div class="task-section">
      <span class="task-label">Current Task</span>
      <div class="task-content">{agent.currentTask}</div>
    </div>
  {/if}

  <!-- Message agent -->
  {#if !isTerminal}
    <div class="message-section">
      <span class="task-label">Message Agent</span>
      <div class="message-input-row">
        <input
          class="message-input"
          type="text"
          placeholder="Send a message..."
          bind:value={messageText}
          onkeydown={handleMessageKeydown}
          disabled={isTerminal}
        />
        <button
          class="btn btn-accent"
          onclick={sendMessage}
          disabled={!messageText.trim() || isTerminal}
        >Send</button>
      </div>
    </div>
  {/if}

  <!-- Actions -->
  <div class="actions">
    {#if isRenaming}
      <button class="btn btn-accent" onclick={submitRename}>Save</button>
      <button class="btn btn-secondary" onclick={cancelRename}>Cancel</button>
    {:else}
      <button class="btn btn-accent" onclick={startRename}>Rename</button>
    {/if}
    <div class="spacer"></div>
    <button class="btn btn-secondary" onclick={() => onClose?.()}>Close</button>
  </div>
</aside>

<style>
  .inspector {
    position: absolute;
    right: 0;
    top: 0;
    bottom: 0;
    width: 280px;
    background: var(--surface);
    border-left: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    padding: var(--sp-lg);
    gap: var(--sp-md);
    overflow-y: auto;
    z-index: 20;
  }

  .header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--sp-sm);
  }

  .header-left {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
  }

  .color-dot {
    width: 28px;
    height: 28px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .header-info {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .agent-name {
    font-family: var(--font-mono);
    font-size: 0.9rem;
    font-weight: 600;
    color: var(--text-primary);
  }

  .agent-type {
    font-size: 0.7rem;
    color: var(--text-secondary);
  }

  .rename-input {
    font-family: var(--font-mono);
    font-size: 0.85rem;
    color: var(--text-primary);
    background: var(--bg);
    border: 1px solid var(--accent);
    border-radius: var(--r-sm);
    padding: 2px 6px;
    outline: none;
    width: 120px;
  }

  .status-badge {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    font-weight: 700;
    padding: 3px 8px;
    border-radius: var(--r-full);
    white-space: nowrap;
  }

  .divider {
    height: 1px;
    background: var(--border);
  }

  .details {
    display: flex;
    flex-direction: column;
    gap: var(--sp-sm);
  }

  .detail-row {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
  }

  .detail-label {
    font-size: 0.7rem;
    color: var(--text-tertiary);
    width: 70px;
    flex-shrink: 0;
  }

  .detail-value {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    color: var(--text-secondary);
  }

  .task-section {
    display: flex;
    flex-direction: column;
    gap: var(--sp-xs);
  }

  .task-label {
    font-size: 0.7rem;
    color: var(--text-tertiary);
  }

  .task-content {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    color: var(--text-primary);
    background: var(--bg);
    padding: var(--sp-sm);
    border-radius: var(--r-sm);
    word-break: break-word;
  }

  .message-section {
    display: flex;
    flex-direction: column;
    gap: var(--sp-xs);
  }

  .message-input-row {
    display: flex;
    gap: var(--sp-xs);
  }

  .message-input {
    flex: 1;
    font-family: var(--font-mono);
    font-size: 0.75rem;
    color: var(--text-primary);
    background: var(--bg);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    padding: 4px 8px;
    outline: none;
  }

  .message-input:focus {
    border-color: var(--accent);
  }

  .message-input:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .actions {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    margin-top: auto;
  }

  .spacer {
    flex: 1;
  }

  .btn {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    padding: 4px 12px;
    border-radius: var(--r-sm);
    border: 1px solid var(--border);
    cursor: pointer;
    transition: background 0.15s;
  }

  .btn-accent {
    color: var(--accent);
    background: transparent;
    border-color: var(--accent-dim);
  }
  .btn-accent:hover {
    background: rgba(212, 168, 83, 0.1);
  }

  .btn-secondary {
    color: var(--text-tertiary);
    background: transparent;
  }
  .btn-secondary:hover {
    background: var(--surface-hover);
  }
</style>
