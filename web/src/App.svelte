<script lang="ts">
  import ConnectionBar from './lib/components/ConnectionBar.svelte';
  import ConnectionStatus from './lib/components/ConnectionStatus.svelte';
  import SessionInfo from './lib/components/SessionInfo.svelte';
  import ChatView from './lib/components/ChatView.svelte';
  import Toast from './lib/components/Toast.svelte';
  import OfficeCanvas from './lib/components/OfficeCanvas.svelte';
  import AgentInspector from './lib/components/AgentInspector.svelte';
  import { relay } from './lib/stores/relay.svelte';
  import { toasts } from './lib/stores/toast.svelte';
  import { createOfficeState } from './lib/office/state.svelte';
  import type { OfficeView } from './lib/office/types';
  import { OFFICE_VIEWS } from './lib/office/layout';
  import NotificationToggle from './lib/components/NotificationToggle.svelte';
  import AuthSettings from './lib/components/AuthSettings.svelte';
  import PairingScreen from './lib/components/PairingScreen.svelte';
  import CharacterGallery from './lib/components/CharacterGallery.svelte';
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
      resendPushSubscription(relay.authToken ?? undefined);

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

  const office = createOfficeState();

  // Expose for debug/demo
  (window as any).__office = office;

  // Wire relay agent events to office state.
  // We track which agents have been processed to avoid duplicate handling.
  // Composite key includes status + task so task changes within the same status are caught.
  let processedAgentStates = $state<Map<string, string>>(new Map());

  $effect(() => {
    // Clear tracking and office state when relay agents are reset (e.g. newSession)
    if (relay.agents.length === 0 && processedAgentStates.size > 0) {
      processedAgentStates.clear();
      office.reset();
      return;
    }

    const agents = relay.agents;
    for (const agent of agents) {
      const key = `${agent.status}::${agent.task}`;
      const prevKey = processedAgentStates.get(agent.id);
      if (prevKey === key) continue;

      processedAgentStates.set(agent.id, key);

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

  // Auto-populate office with idle characters when tab is active and nothing is going on
  $effect(() => {
    if (activeTab === 'office') {
      // Small delay so canvas mounts and engine starts first
      const timer = setTimeout(() => office.ensureAutoIdle(), 150);
      return () => clearTimeout(timer);
    }
  });

  function handleAgentClick(agentId: string) {
    office.selectAgent(agentId);
  }

  function handleRename(newName: string) {
    if (office.selectedAgent) {
      office.renameAgent(office.selectedAgent.id, newName);
    }
  }
</script>

<div class="app">
  <header class="header">
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
      disabled={!office.canDemo && !office.demoMode}
      onclick={() => office.toggleDemo()}
      title={office.demoMode ? 'Exit demo' : 'Launch demo office'}
    >
      {office.demoMode ? '■ Demo' : '▶ Demo'}
    </button>
    <div class="header-spacer"></div>
    <div class="header-actions">
      <AuthSettings />
      <NotificationToggle />
    </div>
  </header>
  <ConnectionBar />
  <ConnectionStatus />
  <SessionInfo />

  {#if activeTab === 'office'}
    <nav class="view-tabs">
      {#each OFFICE_VIEWS as view}
        <button
          class="view-tab"
          class:active={activeView === view.id}
          onclick={() => (activeView = view.id)}
        >
          {view.label}
        </button>
      {/each}
    </nav>
  {/if}

  <div class="main-content">
    {#if activeTab === 'chat'}
      <ChatView />
    {:else if activeTab === 'characters'}
      <CharacterGallery />
    {:else}
      <div class="office-wrapper" class:demo-active={office.demoMode}>
        <OfficeCanvas
          engine={office.engine}
          desks={office.desks}
          onAgentClick={handleAgentClick}
          onEmptyClick={() => office.dismissInspector()}
          activeView={activeView}
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

  {#if !relay.authToken}
    <PairingScreen />
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

  /* Hide auth & notification settings on mobile — accessible via ConnectionBar */
  @media (max-width: 600px) {
    .header-actions {
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
