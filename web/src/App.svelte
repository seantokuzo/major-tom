<script lang="ts">
  import { untrack } from 'svelte';
  import ConnectionBar from './lib/components/ConnectionBar.svelte';
  import ConnectionStatus from './lib/components/ConnectionStatus.svelte';
  import SessionInfo from './lib/components/SessionInfo.svelte';
  import ChatView from './lib/components/ChatView.svelte';
  import Terminal from './lib/components/Terminal.svelte';
  import Toast from './lib/components/Toast.svelte';
  import OfficeCanvas from './lib/components/OfficeCanvas.svelte';
  import AgentInspector from './lib/components/AgentInspector.svelte';
  import { relay } from './lib/stores/relay.svelte';
  import { toasts } from './lib/stores/toast.svelte';
  import { createOfficeSessionManager } from './lib/office/session-manager.svelte';
  import type { OfficeView } from './lib/office/types';
  import { OFFICE_VIEWS } from './lib/office/layout';
  import { sessionsStore } from './lib/stores/sessions.svelte';
  import NotificationToggle from './lib/components/NotificationToggle.svelte';
  import NotificationSettings from './lib/components/NotificationSettings.svelte';
  import AuthSettings from './lib/components/AuthSettings.svelte';
  import UserMenu from './lib/components/UserMenu.svelte';
  import LoginScreen from './lib/components/LoginScreen.svelte';
  import CharacterGallery from './lib/components/CharacterGallery.svelte';
  import PermissionModeSwitcher from './lib/components/PermissionModeSwitcher.svelte';
  import SessionPanel from './lib/components/SessionPanel.svelte';
  import FleetPanel from './lib/components/FleetPanel.svelte';
  import FleetIndicator from './lib/components/FleetIndicator.svelte';
  import AnalyticsPanel from './lib/components/AnalyticsPanel.svelte';
  import AnalyticsIndicator from './lib/components/AnalyticsIndicator.svelte';
  import GitIndicator from './lib/components/GitIndicator.svelte';
  import GitPanel from './lib/components/GitPanel.svelte';
  import GitHubIndicator from './lib/components/GitHubIndicator.svelte';
  import GitHubPanel from './lib/components/GitHubPanel.svelte';
  import AchievementPanel from './lib/components/AchievementPanel.svelte';
  import AchievementIndicator from './lib/components/AchievementIndicator.svelte';
  import ActivityIndicator from './lib/components/ActivityIndicator.svelte';
  import AdminIndicator from './lib/components/AdminIndicator.svelte';
  import { sessionStateManager } from './lib/stores/session-state.svelte';
  import { resendPushSubscription } from './lib/push/push-manager';

  // ── Toast notifications for connection state ────────────────

  let prevState = $state(relay.connectionState);
  let wasReconnecting = $state(false);

  $effect(() => {
    const state = relay.connectionState;
    if (state === prevState) return;
    const was = prevState;
    prevState = state;

    if (state === 'connected') {
      // Re-send push subscription on every connect (relay may have restarted)
      resendPushSubscription();

      if (wasReconnecting) {
        toasts.success('Reconnected to relay');
        wasReconnecting = false;
      } else {
        toasts.success('Connected to relay');
      }
    } else if (state === 'reconnecting') {
      wasReconnecting = true;
      if (was === 'connected') {
        toasts.warning('Connection lost, reconnecting...');
      }
    } else if (state === 'disconnected' && relay.connectionError) {
      wasReconnecting = false;
      toasts.error(relay.connectionError);
    }
  });

  // Separate effect for connectionError set after state transition (e.g. max retries)
  let prevError = $state<string | null>(null);
  $effect(() => {
    const error = relay.connectionError;
    if (error && error !== prevError && relay.isDisconnected) {
      toasts.error(error);
    }
    prevError = error;
  });

  // ── Office state & tab management ─────────────────────────

  type ViewTab = 'chat' | 'office' | 'characters';
  let activeTab = $state<ViewTab>('chat');
  let activeView = $state<OfficeView>('office');
  let headerCollapsed = $state(false);

  const officeManager = createOfficeSessionManager();

  // Convenience: derived ref to the active session's office state
  const office = $derived(officeManager.active);

  // Expose for debug/demo (dev-only)
  if (import.meta.env.DEV) {
    (window as any).__office = officeManager;
  }

  // ── Per-session state switching ─────────────────────────────
  // When relay.sessionId changes, switch the office to that session's state.
  // Derive session name from sessionsStore metadata when available.
  $effect(() => {
    const sessionId = relay.sessionId;
    const sessions = sessionsStore.sessions;

    untrack(() => {
      const meta = sessions.find(s => s.id === sessionId);
      const name = meta?.workingDirName ?? undefined;
      officeManager.switchTo(sessionId, name);
    });
  });

  // Lazy rendering: OfficeCanvas is only mounted when activeTab === 'office'
  // (via Svelte {#if}), so its $effect lifecycle automatically starts/stops
  // the engine. No additional pause/resume logic needed here.

  // Wire relay agent events to office state.
  // We track which agents have been processed to avoid duplicate handling.
  // Composite key includes status + task so task changes within the same status are caught.
  let processedAgentStates = $state<Map<string, string>>(new Map());

  $effect(() => {
    // Subscribe to relay.agents (the trigger) but untrack office mutations
    // to avoid read-write cycles on office.agents within this effect.
    const agents = relay.agents;
    const agentCount = agents.length; // Track array length to fire on push/splice
    const stateSize = processedAgentStates.size;

    untrack(() => {
      // Clear tracking and office state when relay agents are reset (e.g. newSession)
      if (agentCount === 0 && stateSize > 0) {
        processedAgentStates.clear();
        office.reset();
        return;
      }

      for (const agent of agents) {
        const key = `${agent.status}::${agent.task}`;
        const prevKey = processedAgentStates.get(agent.id);
        if (prevKey === key) continue;

        processedAgentStates.set(agent.id, key);

        // Always ensure handleSpawn is called first for new agents.
        // Svelte 5 batches reactive updates — if agent.spawn and agent.working
        // arrive in the same microtask, the effect may only fire once with
        // the agent already in 'working' state. Without this guard,
        // handleSpawn would never be called and the sprite never promotes.
        const isNew = !prevKey;
        if (isNew && agent.status !== 'spawned') {
          office.handleSpawn(agent.id, agent.role, agent.task);
        }

        switch (agent.status) {
          case 'spawned':
            office.handleSpawn(agent.id, agent.role, agent.task);
            break;
          case 'working':
            office.handleWorking(agent.id, agent.task);
            break;
          case 'idle':
            office.handleIdle(agent.id);
            break;
          case 'complete':
            office.handleComplete(agent.id, agent.result ?? agent.task);
            break;
          case 'dismissed':
            office.handleDismissed(agent.id);
            break;
        }
      }
    });
  });

  // Session mode: when relay is connected with an active session, populate crew as idle
  // When disconnected or no session, exit session mode
  // Not gated on activeTab — agents can spawn while on Chat tab
  $effect(() => {
    const hasSession = relay.isConnected && relay.hasSession;

    const timer = setTimeout(() => {
      if (hasSession) {
        office.enterSessionMode();
      } else if (office.sessionMode) {
        office.exitSessionMode();
      }
    }, 150);
    return () => clearTimeout(timer);
  });

  // Auto-idle fallback: when no session and no agents, start demo
  // This is separate so it reacts to canDemo becoming true after cleanup
  $effect(() => {
    if (activeTab !== 'office') return;
    if (office.sessionMode) return;
    if (!office.canDemo) return;
    if (office.demoMode) return;

    const timer = setTimeout(() => office.ensureAutoIdle(), 200);
    return () => clearTimeout(timer);
  });

  function handleAgentClick(agentId: string) {
    office.selectAgent(agentId);
  }

  function handleRename(newName: string) {
    if (office.selectedAgent) {
      office.renameAgent(office.selectedAgent.id, newName);
    }
  }

  // Auto-connect when user is authenticated and relay is disconnected (but not manually)
  $effect(() => {
    if (relay.user && relay.isDisconnected && !relay.connectionError && !relay.manuallyDisconnected) {
      relay.connect();
    }
  });
</script>

<div class="app">
  <header class="header">
    <button
      class="collapse-btn"
      onclick={() => (headerCollapsed = !headerCollapsed)}
      title={headerCollapsed ? 'Expand header' : 'Collapse header'}
      aria-label={headerCollapsed ? 'Expand header' : 'Collapse header'}
    >
      {headerCollapsed ? '\u25B6' : '\u25BC'}
    </button>
    {#if !headerCollapsed}
      <h1 class="title">MT</h1>
      <nav class="tabs">
        <button
          class="tab"
          class:active={activeTab === 'chat'}
          onclick={() => (activeTab = 'chat')}
        >
          Chat
        </button>
        <button
          class="tab"
          class:active={activeTab === 'office'}
          onclick={() => (activeTab = 'office')}
        >
          Office
          {#if office.agents.length > 0}
            <span class="agent-count">{office.agents.length}</span>
          {/if}
        </button>
        <button
          class="tab"
          class:active={activeTab === 'characters'}
          onclick={() => (activeTab = 'characters')}
        >
          Crew
        </button>
      </nav>
      <button
        class="demo-btn"
        class:active={office.demoMode}
        disabled={(!office.canDemo && !office.demoMode) || office.sessionMode}
        onclick={() => office.toggleDemo()}
        title={office.sessionMode ? 'Demo disabled during active session' : office.demoMode ? 'Exit demo' : 'Launch demo office'}
      >
        {office.demoMode ? '■ Demo' : '▶ Demo'}
      </button>
      <div class="header-spacer"></div>
      {#if relay.hasSession && relay.sessionName}
        <span class="session-label" title={relay.sessionName}>{relay.sessionName}</span>
      {/if}
      <div class="header-actions">
        {#if relay.multiUserEnabled}
          <span class="team-badge">Team</span>
          <UserMenu />
        {/if}
        <AdminIndicator />
        <span class="header-settings">
          <AuthSettings />
          <NotificationToggle />
          <NotificationSettings />
        </span>
        <AchievementIndicator />
        {#if relay.multiUserEnabled}
          <ActivityIndicator />
        {/if}
        <GitIndicator />
        <GitHubIndicator />
        <AnalyticsIndicator />
        <FleetIndicator />
        <button
          class="hamburger-btn"
          onclick={() => sessionStateManager.togglePanel()}
          title="Sessions"
          aria-label="Toggle session panel"
          disabled={!relay.isConnected}
        >
          &#9776;
        </button>
      </div>
    {:else}
      <span class="collapsed-status">
        {relay.permissionMode.mode.toUpperCase()}
        {#if relay.isConnected}
          <span class="collapsed-dot connected"></span>
        {:else}
          <span class="collapsed-dot"></span>
        {/if}
      </span>
    {/if}
  </header>
  {#if !headerCollapsed}
    <ConnectionBar />
    <ConnectionStatus />
    {#if relay.isConnected && relay.hasSession}
      <div
        class="mode-row"
        class:mode-row-yolo={relay.permissionMode.mode === 'god' && relay.permissionMode.godSubMode === 'yolo'}
      >
        <PermissionModeSwitcher />
      </div>
    {/if}
    <SessionInfo />
  {/if}

  {#if activeTab === 'office'}
    <nav class="view-tabs">
      {#each OFFICE_VIEWS as view}
        {@const count = office.agents.filter(a => { const ea = office.engine.agents.get(a.id); return (ea?.currentView ?? 'office') === view.id; }).length}
        <button
          class="view-tab"
          class:active={activeView === view.id}
          onclick={() => (activeView = view.id)}
        >
          {view.label}
          {#if count > 0}
            <span class="view-count">{count}</span>
          {/if}
        </button>
      {/each}
    </nav>
  {/if}

  <div class="main-content">
    {#if activeTab === 'chat'}
      {#if relay.isConnected && !relay.hasSession}
        <Terminal />
      {:else}
        <ChatView />
      {/if}
    {:else if activeTab === 'characters'}
      <CharacterGallery />
    {:else}
      <div class="office-wrapper" class:demo-active={office.demoMode}>
        {#if officeManager.activeSessionId}
          <div class="session-badge">{officeManager.activeSessionName}</div>
        {/if}
        <OfficeCanvas
          engine={office.engine}
          desks={office.desks}
          onAgentClick={handleAgentClick}
          onEmptyClick={() => office.dismissInspector()}
          activeView={activeView}
          themeEngine={office.themeEngine}
          moodEngine={office.moodEngine}
        />
        {#if office.selectedAgent}
          <AgentInspector
            agent={office.selectedAgent}
            onRename={handleRename}
            onClose={() => office.dismissInspector()}
          />
        {/if}
      </div>
    {/if}
  </div>
  <Toast />
  <SessionPanel />
  <GitPanel />
  <GitHubPanel />
  <FleetPanel />
  <AnalyticsPanel />
  <AchievementPanel />

  {#if relay.authChecked && !relay.user}
    <LoginScreen />
  {/if}
</div>

<style>
  .app {
    height: 100%;
    display: flex;
    flex-direction: column;
  }

  .header {
    padding: var(--sp-xs) var(--sp-sm);
    background: var(--bg);
    flex-shrink: 0;
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    overflow: hidden;
  }

  .mode-row {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 3px var(--sp-sm);
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
    transition: background 0.3s, border-color 0.3s;
  }

  .mode-row-yolo {
    background: rgba(248, 113, 113, 0.04);
    border-bottom-color: rgba(248, 113, 113, 0.3);
  }

  .collapse-btn {
    width: 24px;
    height: 24px;
    border: none;
    background: transparent;
    color: var(--text-tertiary);
    font-size: 0.55rem;
    cursor: pointer;
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: var(--r-sm);
    transition: all 0.15s;
  }

  .collapse-btn:hover {
    color: var(--text-secondary);
    background: var(--surface-hover);
  }

  .collapsed-status {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    font-weight: 600;
    color: var(--text-secondary);
    letter-spacing: 0.05em;
    display: flex;
    align-items: center;
    gap: var(--sp-xs);
  }

  .collapsed-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: var(--deny);
  }

  .collapsed-dot.connected {
    background: var(--allow);
  }

  .title {
    font-family: var(--font-mono);
    font-size: 0.8rem;
    font-weight: 700;
    color: var(--accent);
    letter-spacing: 0.08em;
    text-transform: uppercase;
    flex-shrink: 0;
  }

  .tabs {
    display: flex;
    gap: 2px;
    background: var(--surface);
    border-radius: var(--r-sm);
    padding: 2px;
    flex-shrink: 0;
  }

  .tab {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    font-weight: 500;
    color: var(--text-tertiary);
    background: transparent;
    border: none;
    padding: 6px 10px;
    border-radius: 4px;
    cursor: pointer;
    transition: all 0.15s;
    display: flex;
    align-items: center;
    gap: 6px;
    min-height: 32px;
  }

  .tab:hover {
    color: var(--text-secondary);
  }

  .tab.active {
    color: var(--text-primary);
    background: var(--surface-hover);
  }

  .header-spacer {
    flex: 1;
    min-width: 0;
  }

  .header-actions {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    flex-shrink: 0;
  }

  .team-badge {
    font-family: var(--font-mono);
    font-size: 0.5rem;
    font-weight: 700;
    color: var(--bg);
    background: var(--accent-dim);
    padding: 1px 6px;
    border-radius: var(--r-full);
    text-transform: uppercase;
    letter-spacing: 0.06em;
    line-height: 1.4;
    flex-shrink: 0;
  }

  /* Hide auth & notification settings on mobile — accessible via ConnectionBar.
     But keep hamburger visible. Use a wrapper span to target hiding. */
  @media (max-width: 600px) {
    .header-settings {
      display: none;
    }
  }

  .header-settings {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
  }

  .hamburger-btn {
    background: transparent;
    border: 1px solid var(--border);
    color: var(--text-secondary);
    font-size: 1.1rem;
    cursor: pointer;
    padding: 4px 8px;
    border-radius: var(--r-sm);
    transition: all 0.15s;
    display: flex;
    align-items: center;
    justify-content: center;
    line-height: 1;
  }

  .hamburger-btn:hover:not(:disabled) {
    color: var(--text-primary);
    background: var(--surface-hover);
    border-color: var(--accent);
  }

  .hamburger-btn:disabled {
    opacity: 0.3;
    cursor: not-allowed;
  }

  .session-label {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    font-weight: 600;
    color: var(--text-secondary);
    max-width: 120px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    flex-shrink: 1;
    min-width: 0;
  }

  @media (max-width: 400px) {
    .session-label {
      display: none;
    }
  }

  .agent-count {
    font-size: 0.6rem;
    font-weight: 700;
    background: var(--accent-dim);
    color: var(--bg);
    padding: 1px 5px;
    border-radius: var(--r-full);
    line-height: 1.2;
  }

  .view-tabs {
    display: flex;
    gap: 2px;
    padding: 0 var(--sp-sm);
    padding-bottom: 4px;
    background: var(--bg);
    flex-shrink: 0;
  }

  .view-tab {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    font-weight: 500;
    color: var(--text-tertiary);
    background: transparent;
    border: none;
    border-bottom: 2px solid transparent;
    padding: 4px 8px;
    cursor: pointer;
    transition: all 0.15s;
  }

  .view-tab:hover {
    color: var(--text-secondary);
  }

  .view-tab.active {
    color: var(--accent);
    border-bottom-color: var(--accent);
  }

  .view-count {
    font-size: 0.55rem;
    font-weight: 700;
    background: rgba(200, 200, 210, 0.2);
    color: var(--text-tertiary);
    padding: 0 4px;
    border-radius: var(--r-full);
    margin-left: 3px;
  }

  .view-tab.active .view-count {
    background: rgba(var(--accent-rgb, 77, 217, 115), 0.2);
    color: var(--accent);
  }

  .main-content {
    flex: 1;
    display: flex;
    flex-direction: column;
    min-height: 0;
    overflow: hidden;
  }

  .office-wrapper {
    flex: 1;
    position: relative;
    display: flex;
    min-height: 0;
  }

  .session-badge {
    position: absolute;
    top: 6px;
    left: 50%;
    transform: translateX(-50%);
    z-index: 10;
    font-family: var(--font-mono);
    font-size: 0.6rem;
    font-weight: 600;
    color: var(--text-tertiary);
    background: rgba(30, 30, 40, 0.85);
    border: 1px solid var(--border);
    padding: 2px 10px;
    border-radius: var(--r-full);
    pointer-events: none;
    white-space: nowrap;
    letter-spacing: 0.03em;
  }

  .office-wrapper.demo-active {
    box-shadow: inset 0 0 20px rgba(77, 217, 115, 0.15);
  }

  .demo-btn {
    padding: 2px 10px;
    font-family: Menlo, monospace;
    font-size: 11px;
    font-weight: bold;
    color: rgb(77, 217, 115);
    background: transparent;
    border: 1px solid rgb(77, 217, 115);
    border-radius: 4px;
    cursor: pointer;
    transition: all 0.15s;
    margin-left: 8px;
    flex-shrink: 0;
  }

  .demo-btn:hover:not(:disabled) {
    background: rgba(77, 217, 115, 0.15);
  }

  .demo-btn:disabled {
    opacity: 0.3;
    cursor: not-allowed;
  }

  .demo-btn.active {
    background: rgb(77, 217, 115);
    color: rgb(30, 30, 30);
    animation: demo-pulse 1.5s infinite alternate;
  }

  @keyframes demo-pulse {
    from { box-shadow: 0 0 4px rgba(77, 217, 115, 0.4); }
    to { box-shadow: 0 0 10px rgba(77, 217, 115, 0.6); }
  }
</style>
