<script lang="ts">
  import { onMount } from 'svelte';
  import { relay } from '../stores/relay.svelte';
  import { sessionStateManager } from '../stores/session-state.svelte';
  import { presenceStore } from '../stores/presence.svelte';
  import { fleetStore } from '../stores/fleet.svelte';
  import { analyticsStore } from '../stores/analytics.svelte';
  import { achievementStore } from '../stores/achievements.svelte';
  import { initPushNotifications, unsubscribeFromPush } from '../push/push-manager';
  import { toasts } from '../stores/toast.svelte';
  import PresenceAvatars from './PresenceAvatars.svelte';

  const showPresence = $derived(relay.multiUserEnabled);

  // ── Notification state ────────────────────────────────────
  let notifPermission = $state<NotificationPermission | 'unsupported'>(
    typeof Notification !== 'undefined' ? Notification.permission : 'unsupported',
  );
  let notifSubscribed = $state(false);
  let notifLoading = $state(false);

  onMount(() => {
    checkNotifSubscription();
  });

  async function checkNotifSubscription() {
    if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
      notifPermission = 'unsupported';
      return;
    }
    try {
      const reg = await navigator.serviceWorker.getRegistration();
      if (!reg) return;
      const sub = await reg.pushManager.getSubscription();
      notifSubscribed = sub !== null;
    } catch { /* silently degrade */ }
  }

  async function toggleNotifications() {
    notifLoading = true;
    try {
      if (notifSubscribed) {
        const reg = await navigator.serviceWorker.getRegistration();
        const sub = reg ? await reg.pushManager.getSubscription() : null;
        if (sub) await unsubscribeFromPush(sub);
        notifSubscribed = false;
        toasts.info('Notifications disabled');
      } else {
        const status = await initPushNotifications();
        notifPermission = status.permission === 'unsupported' ? 'unsupported' : status.permission;
        notifSubscribed = status.subscribed;
        if (status.permission === 'denied') {
          toasts.warning('Notifications blocked — enable in browser settings');
        } else if (status.subscribed) {
          toasts.success('Notifications enabled');
        } else if (status.error) {
          toasts.error(status.error);
        }
      }
    } catch {
      toasts.error('Notification toggle failed');
    } finally {
      notifLoading = false;
    }
  }

  // Collapsible section state
  let sessionsOpen = $state(false);
  let toolsOpen = $state(false);

  // Request session list whenever drawer opens
  $effect(() => {
    if (sessionStateManager.panelOpen) {
      relay.requestSessionList();
    }
  });

  // Close on Escape key
  $effect(() => {
    if (!sessionStateManager.panelOpen) return;
    function onKeydown(e: KeyboardEvent) {
      if (e.key === 'Escape') {
        sessionStateManager.closePanel();
      }
    }
    window.addEventListener('keydown', onKeydown);
    return () => window.removeEventListener('keydown', onKeydown);
  });

  function close() {
    sessionStateManager.closePanel();
  }

  // ── Session helpers ───────────────────────────────────────

  function formatCost(cost: number): string {
    if (cost === 0) return '$0';
    return `$${cost.toFixed(4)}`;
  }

  function truncateDir(dir: string, maxLen = 28): string {
    if (!dir) return '';
    if (dir.length <= maxLen) return dir;
    return '...' + dir.slice(-maxLen + 3);
  }

  function handleSessionClick(sessionId: string) {
    if (sessionId === relay.sessionId) {
      close();
      return;
    }
    relay.switchSession(sessionId);
    close();
  }

  function handleNewSession() {
    relay.newSession();
    close();
  }

  // Editable name state
  let editingId = $state<string | null>(null);
  let editValue = $state('');

  function startRename(sessionId: string, currentName: string, e: Event) {
    e.stopPropagation();
    editingId = sessionId;
    editValue = currentName;
  }

  function commitRename() {
    if (editingId && editValue.trim()) {
      sessionStateManager.renameSession(editingId, editValue.trim());
    }
    editingId = null;
    editValue = '';
  }

  function cancelRename() {
    editingId = null;
    editValue = '';
  }

  // ── Tool panel launchers ──────────────────────────────────

  function openPanel(toggle: () => void) {
    close();
    // Small delay so the drawer closes before panel opens (avoids z-index fight)
    requestAnimationFrame(() => toggle());
  }

  // ── Connection actions ────────────────────────────────────

  function handleDisconnect() {
    relay.disconnect();
    close();
  }
</script>

{#if sessionStateManager.panelOpen}
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="drawer-backdrop" onclick={close}>
    <!-- svelte-ignore a11y_click_events_have_key_events -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="drawer" onclick={(e) => e.stopPropagation()}>

      <!-- Header -->
      <div class="drawer-header">
        <span class="drawer-title">Menu</span>
        <div class="connection-badge">
          <span
            class="conn-dot"
            class:connected={relay.isConnected}
          ></span>
          <span class="conn-label">
            {relay.isConnected ? 'Connected' : 'Disconnected'}
          </span>
        </div>
        <button class="drawer-close" onclick={close} aria-label="Close">&times;</button>
      </div>

      <!-- Scrollable body -->
      <div class="drawer-body">

        <!-- ── Sessions section ──────────────────────────── -->
        <button class="section-header" onclick={() => sessionsOpen = !sessionsOpen}>
          <span class="section-chevron">{sessionsOpen ? '\u25BC' : '\u25B6'}</span>
          <span class="section-label">Sessions</span>
          {#if sessionStateManager.sessionList.length > 0}
            <span class="section-count">{sessionStateManager.sessionList.length}</span>
          {/if}
        </button>

        {#if sessionsOpen}
          <div class="section-content">
            <button class="new-session-btn" onclick={handleNewSession} disabled={!relay.isConnected}>
              <span class="new-icon">+</span>
              New Session
            </button>

            {#if sessionStateManager.sessionList.length === 0}
              <div class="section-empty">No sessions yet</div>
            {:else}
              {#each sessionStateManager.sessionList as entry (entry.sessionId)}
                <div
                  class="session-item"
                  class:current={entry.sessionId === relay.sessionId}
                  role="button"
                  tabindex="0"
                  onclick={() => handleSessionClick(entry.sessionId)}
                  onkeydown={(e) => {
                    if (e.key === 'Enter' || e.key === ' ') {
                      e.preventDefault();
                      handleSessionClick(entry.sessionId);
                    }
                  }}
                >
                  <div class="session-row-top">
                    <span
                      class="status-dot"
                      class:dot-active={entry.status === 'active'}
                      class:dot-idle={entry.status === 'idle'}
                      class:dot-closed={entry.status === 'closed'}
                      title={entry.status}
                    ></span>
                    {#if editingId === entry.sessionId}
                      <!-- svelte-ignore a11y_autofocus -->
                      <input
                        class="rename-input"
                        bind:value={editValue}
                        onkeydown={(e) => { if (e.key === 'Enter') commitRename(); if (e.key === 'Escape') cancelRename(); }}
                        onblur={commitRename}
                        onclick={(e) => e.stopPropagation()}
                        autofocus
                      />
                    {:else}
                      <span class="session-name">
                        {entry.name}
                      </span>
                      <button
                        class="rename-btn"
                        onclick={(e) => startRename(entry.sessionId, entry.name, e)}
                        aria-label="Rename session"
                      >&#9998;</button>
                    {/if}
                    {#if entry.sessionId === relay.sessionId}
                      <span class="current-badge">current</span>
                    {/if}
                    {#if showPresence}
                      {@const watchers = presenceStore.watchersFor(entry.sessionId)}
                      {#if watchers.length > 0}
                        <PresenceAvatars users={watchers} maxShow={2} size="sm" />
                      {/if}
                    {/if}
                  </div>
                  <div class="session-row-meta">
                    {#if entry.workingDir}
                      <span class="meta-dir" title={entry.workingDir}>{truncateDir(entry.workingDir)}</span>
                    {/if}
                    <span class="meta-cost">{formatCost(entry.totalCost)}</span>
                    {#if entry.agentCount > 0}
                      <span class="meta-agents">{entry.agentCount} agent{entry.agentCount !== 1 ? 's' : ''}</span>
                    {/if}
                  </div>
                </div>
              {/each}
            {/if}
          </div>
        {/if}

        <!-- ── Tools section ─────────────────────────────── -->
        <button class="section-header" onclick={() => toolsOpen = !toolsOpen}>
          <span class="section-chevron">{toolsOpen ? '\u25BC' : '\u25B6'}</span>
          <span class="section-label">Tools</span>
        </button>

        {#if toolsOpen}
          <div class="section-content">
            <button
              class="menu-item"
              onclick={() => openPanel(() => relay.toggleGitPanel())}
              disabled={!relay.isConnected || !relay.hasSession}
            >
              <span class="menu-icon">
                <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor">
                  <path d="M9.5 3.25a2.25 2.25 0 1 1 3 2.122V6A2.5 2.5 0 0 1 10 8.5H6a1 1 0 0 0-1 1v1.128a2.251 2.251 0 1 1-1.5 0V5.372a2.25 2.25 0 1 1 1.5 0v1.836A2.493 2.493 0 0 1 6 7h4a1 1 0 0 0 1-1v-.628A2.25 2.25 0 0 1 9.5 3.25Z"/>
                </svg>
              </span>
              Git
              {#if relay.gitBranch}
                <span class="menu-detail">{relay.gitBranch}</span>
              {/if}
            </button>

            <button
              class="menu-item"
              onclick={() => openPanel(() => relay.toggleGitHubPanel())}
              disabled={!relay.isConnected || !relay.hasSession}
            >
              <span class="menu-icon">
                <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor">
                  <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8Z"/>
                </svg>
              </span>
              GitHub
            </button>

            <button
              class="menu-item"
              onclick={() => openPanel(() => relay.toggleCIPanel())}
              disabled={!relay.isConnected || !relay.hasSession}
            >
              <span class="menu-icon">CI</span>
              CI / Actions
            </button>

            <button
              class="menu-item"
              onclick={() => openPanel(() => fleetStore.togglePanel())}
              disabled={!relay.isConnected}
            >
              <span class="menu-icon">
                <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor">
                  <path d="M1 2.5A1.5 1.5 0 0 1 2.5 1h3A1.5 1.5 0 0 1 7 2.5v3A1.5 1.5 0 0 1 5.5 7h-3A1.5 1.5 0 0 1 1 5.5v-3Zm8 0A1.5 1.5 0 0 1 10.5 1h3A1.5 1.5 0 0 1 15 2.5v3A1.5 1.5 0 0 1 13.5 7h-3A1.5 1.5 0 0 1 9 5.5v-3Zm-8 8A1.5 1.5 0 0 1 2.5 9h3A1.5 1.5 0 0 1 7 10.5v3A1.5 1.5 0 0 1 5.5 15h-3A1.5 1.5 0 0 1 1 13.5v-3Zm8 0A1.5 1.5 0 0 1 10.5 9h3a1.5 1.5 0 0 1 1.5 1.5v3a1.5 1.5 0 0 1-1.5 1.5h-3A1.5 1.5 0 0 1 9 13.5v-3Z"/>
                </svg>
              </span>
              Fleet
              {#if fleetStore.totalWorkers > 0}
                <span class="menu-detail">{fleetStore.totalWorkers} workers</span>
              {/if}
            </button>

            <button
              class="menu-item"
              onclick={() => openPanel(() => analyticsStore.togglePanel())}
              disabled={!relay.isConnected}
            >
              <span class="menu-icon">
                <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor">
                  <path d="M1 11.5v2A1.5 1.5 0 0 0 2.5 15h1A1.5 1.5 0 0 0 5 13.5v-2A1.5 1.5 0 0 0 3.5 10h-1A1.5 1.5 0 0 0 1 11.5Zm5-5v7A1.5 1.5 0 0 0 7.5 15h1A1.5 1.5 0 0 0 10 13.5v-7A1.5 1.5 0 0 0 8.5 5h-1A1.5 1.5 0 0 0 6 6.5Zm5-5v12a1.5 1.5 0 0 0 1.5 1.5h1a1.5 1.5 0 0 0 1.5-1.5v-12A1.5 1.5 0 0 0 13.5 0h-1A1.5 1.5 0 0 0 11 1.5Z"/>
                </svg>
              </span>
              Analytics
            </button>

            <button
              class="menu-item"
              onclick={() => openPanel(() => achievementStore.togglePanel())}
              disabled={!relay.isConnected}
            >
              <span class="menu-icon">
                <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor">
                  <path d="M8 .25a.75.75 0 0 1 .673.418l1.882 3.815 4.21.612a.75.75 0 0 1 .416 1.279l-3.046 2.97.719 4.192a.751.751 0 0 1-1.088.791L8 12.347l-3.766 1.98a.75.75 0 0 1-1.088-.79l.72-4.194L.818 6.374a.75.75 0 0 1 .416-1.28l4.21-.611L7.327.668A.75.75 0 0 1 8 .25Z"/>
                </svg>
              </span>
              Achievements
            </button>
          </div>
        {/if}

        <!-- ── Notifications ──────────────────────────────── -->
        <div class="notif-row">
          <span class="notif-label">Notifications</span>
          {#if notifPermission === 'unsupported'}
            <span class="notif-status muted">Not supported</span>
          {:else if notifPermission === 'denied'}
            <span class="notif-status blocked">Blocked</span>
          {:else}
            <button
              class="notif-toggle"
              class:on={notifSubscribed}
              onclick={toggleNotifications}
              disabled={notifLoading}
            >
              <span class="notif-track">
                <span class="notif-thumb"></span>
              </span>
              <span class="notif-state">{notifSubscribed ? 'On' : 'Off'}</span>
            </button>
          {/if}
        </div>

      </div>

      <!-- Bottom-pinned disconnect -->
      <div class="drawer-footer">
        {#if relay.isConnected}
          <button class="disconnect-btn" onclick={handleDisconnect}>
            Disconnect
          </button>
        {:else}
          <button class="connect-btn" onclick={() => { relay.connect(); close(); }}>
            Connect
          </button>
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .drawer-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.45);
    z-index: 200;
  }

  .drawer {
    position: fixed;
    top: 0;
    right: 0;
    bottom: 0;
    width: min(300px, 85vw);
    background: var(--bg);
    border-left: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    box-shadow: -4px 0 24px rgba(0, 0, 0, 0.4);
    animation: slide-in 0.2s ease-out;
  }

  @keyframes slide-in {
    from { transform: translateX(100%); }
    to { transform: translateX(0); }
  }

  /* ── Header ──────────────────────────────────────────────── */

  .drawer-header {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    padding: var(--sp-md) var(--sp-lg);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
  }

  .drawer-title {
    font-family: var(--font-mono);
    font-size: 0.85rem;
    font-weight: 600;
    color: var(--text-primary);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .connection-badge {
    display: flex;
    align-items: center;
    gap: 4px;
    margin-left: auto;
    margin-right: var(--sp-sm);
  }

  .conn-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: var(--deny);
  }

  .conn-dot.connected {
    background: var(--allow);
  }

  .conn-label {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    color: var(--text-tertiary);
  }

  .drawer-close {
    background: transparent;
    border: none;
    color: var(--text-secondary);
    font-size: 1.3rem;
    cursor: pointer;
    padding: 0 var(--sp-xs);
    line-height: 1;
  }
  .drawer-close:hover { color: var(--text-primary); }

  /* ── Body ────────────────────────────────────────────────── */

  .drawer-body {
    flex: 1;
    overflow-y: auto;
    padding: var(--sp-xs) 0;
  }

  /* ── Section headers ─────────────────────────────────────── */

  .section-header {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    width: 100%;
    padding: var(--sp-sm) var(--sp-lg);
    background: transparent;
    border: none;
    border-bottom: 1px solid var(--border);
    cursor: pointer;
    color: var(--text-secondary);
    font-family: var(--font-mono);
    font-size: 0.75rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    transition: all 0.15s;
  }

  .section-header:hover {
    color: var(--text-primary);
    background: var(--surface-hover);
  }

  .section-chevron {
    font-size: 0.5rem;
    width: 12px;
    text-align: center;
  }

  .section-count {
    font-size: 0.6rem;
    font-weight: 700;
    background: rgba(200, 200, 210, 0.2);
    color: var(--text-tertiary);
    padding: 0 5px;
    border-radius: var(--r-full);
    margin-left: auto;
  }

  .section-content {
    padding: var(--sp-xs) var(--sp-md);
  }

  .section-empty {
    padding: var(--sp-md);
    text-align: center;
    font-family: var(--font-mono);
    font-size: 0.75rem;
    color: var(--text-tertiary);
  }

  /* ── Sessions ────────────────────────────────────────────── */

  .new-session-btn {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    width: 100%;
    margin-bottom: var(--sp-sm);
    padding: var(--sp-sm) var(--sp-md);
    font-family: var(--font-mono);
    font-size: 0.75rem;
    font-weight: 600;
    color: var(--bg);
    background: var(--accent);
    border: none;
    border-radius: var(--r-sm);
    cursor: pointer;
    transition: all 0.15s;
  }

  .new-session-btn:hover:not(:disabled) { background: var(--accent-dim); }
  .new-session-btn:disabled { opacity: 0.4; cursor: not-allowed; }

  .new-icon {
    font-size: 1rem;
    font-weight: 700;
    line-height: 1;
  }

  .rename-btn {
    background: transparent;
    border: none;
    color: var(--text-tertiary);
    font-size: 0.7rem;
    cursor: pointer;
    padding: 2px 4px;
    border-radius: 3px;
    flex-shrink: 0;
    line-height: 1;
  }

  .rename-btn:hover { color: var(--text-primary); background: var(--surface-hover); }

  .session-item {
    display: block;
    width: 100%;
    padding: var(--sp-sm) var(--sp-md);
    margin-bottom: var(--sp-xs);
    background: transparent;
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    cursor: pointer;
    text-align: left;
    color: var(--text-primary);
    transition: background 0.15s, border-color 0.15s;
  }

  .session-item:hover { background: var(--surface-hover); }
  .session-item.current {
    border-color: var(--accent);
    background: rgba(77, 217, 115, 0.06);
  }

  .session-row-top {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    margin-bottom: 4px;
  }

  .status-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    flex-shrink: 0;
    background: var(--text-tertiary);
  }

  .dot-active { background: var(--allow); box-shadow: 0 0 4px var(--allow); }
  .dot-idle { background: #eab308; }
  .dot-closed { background: var(--text-tertiary); }

  .session-name {
    font-family: var(--font-mono);
    font-size: 0.8rem;
    font-weight: 600;
    color: var(--text-primary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    flex: 1;
    min-width: 0;
    cursor: text;
  }

  .rename-input {
    font-family: var(--font-mono);
    font-size: 0.8rem;
    font-weight: 600;
    color: var(--text-primary);
    background: var(--surface);
    border: 1px solid var(--accent);
    border-radius: 3px;
    padding: 1px 6px;
    flex: 1;
    min-width: 0;
    outline: none;
  }

  .current-badge {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    font-weight: 700;
    color: var(--accent);
    text-transform: uppercase;
    letter-spacing: 0.04em;
    flex-shrink: 0;
  }

  .session-row-meta {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    font-family: var(--font-mono);
    font-size: 0.65rem;
    color: var(--text-tertiary);
    flex-wrap: wrap;
    padding-left: calc(8px + var(--sp-sm));
  }

  .meta-dir {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    max-width: 140px;
  }

  .meta-cost { color: var(--text-secondary); }
  .meta-agents { color: var(--accent-dim); }

  /* ── Menu items (tools) ──────────────────────────────────── */

  .menu-item {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    width: 100%;
    padding: var(--sp-sm) var(--sp-md);
    margin-bottom: 2px;
    background: transparent;
    border: none;
    border-radius: var(--r-sm);
    cursor: pointer;
    color: var(--text-secondary);
    font-family: var(--font-mono);
    font-size: 0.75rem;
    font-weight: 500;
    text-align: left;
    transition: all 0.15s;
  }

  .menu-item:hover:not(:disabled) {
    color: var(--text-primary);
    background: var(--surface-hover);
  }

  .menu-item:disabled {
    opacity: 0.3;
    cursor: not-allowed;
  }

  .menu-icon {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 18px;
    flex-shrink: 0;
    color: var(--text-tertiary);
    font-size: 0.6rem;
    font-weight: 700;
  }

  .menu-detail {
    margin-left: auto;
    font-size: 0.6rem;
    color: var(--text-tertiary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    max-width: 100px;
  }

  /* ── Footer ──────────────────────────────────────────────── */

  .drawer-footer {
    padding: var(--sp-md) var(--sp-lg);
    border-top: 1px solid var(--border);
    flex-shrink: 0;
  }

  .disconnect-btn {
    width: 100%;
    padding: var(--sp-sm) var(--sp-md);
    background: transparent;
    border: 1px solid var(--deny);
    border-radius: var(--r-sm);
    color: var(--deny);
    font-family: var(--font-mono);
    font-size: 0.75rem;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.15s;
  }

  .disconnect-btn:hover {
    background: rgba(248, 113, 113, 0.1);
  }

  .connect-btn {
    width: 100%;
    padding: var(--sp-sm) var(--sp-md);
    background: var(--accent);
    border: none;
    border-radius: var(--r-sm);
    color: var(--bg);
    font-family: var(--font-mono);
    font-size: 0.75rem;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.15s;
  }

  .connect-btn:hover { background: var(--accent-dim); }

  /* ── Notification toggle ─────────────────────────────────── */

  .notif-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--sp-sm) var(--sp-lg);
    border-top: 1px solid var(--border);
  }

  .notif-label {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    font-weight: 600;
    color: var(--text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .notif-status {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    font-weight: 500;
  }

  .notif-status.muted { color: var(--text-tertiary); }
  .notif-status.blocked { color: var(--deny); }

  .notif-toggle {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    background: transparent;
    border: none;
    cursor: pointer;
    padding: 0;
  }

  .notif-toggle:disabled { opacity: 0.5; cursor: not-allowed; }

  .notif-track {
    display: block;
    width: 36px;
    height: 20px;
    border-radius: 10px;
    background: var(--surface-hover);
    border: 1px solid var(--border);
    position: relative;
    transition: all 0.2s;
  }

  .notif-toggle.on .notif-track {
    background: var(--accent);
    border-color: var(--accent);
  }

  .notif-thumb {
    display: block;
    width: 14px;
    height: 14px;
    border-radius: 50%;
    background: var(--text-tertiary);
    position: absolute;
    top: 2px;
    left: 2px;
    transition: all 0.2s;
  }

  .notif-toggle.on .notif-thumb {
    left: 18px;
    background: var(--bg);
  }

  .notif-state {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    font-weight: 500;
    color: var(--text-tertiary);
  }

  .notif-toggle.on .notif-state {
    color: var(--accent);
  }
</style>
