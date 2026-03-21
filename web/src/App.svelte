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

  const office = createOfficeState();

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
    <h1 class="title">Major Tom</h1>
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
    <div class="header-spacer"></div>
    <AuthSettings />
    <NotificationToggle />
  </header>
  <ConnectionBar />
  <ConnectionStatus />
  <SessionInfo />

  <div class="main-content">
    {#if activeTab === 'chat'}
      <ChatView />
    {:else if activeTab === 'characters'}
      <CharacterGallery />
    {:else}
      <div class="office-wrapper">
        <OfficeCanvas
          engine={office.engine}
          desks={office.desks}
          onAgentClick={handleAgentClick}
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
    padding: var(--sp-xs) var(--sp-lg);
    background: var(--bg);
    flex-shrink: 0;
    display: flex;
    align-items: center;
    gap: var(--sp-lg);
  }

  .title {
    font-family: var(--font-mono);
    font-size: 0.85rem;
    font-weight: 700;
    color: var(--accent);
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .tabs {
    display: flex;
    gap: 2px;
    background: var(--surface);
    border-radius: var(--r-sm);
    padding: 2px;
  }

  .tab {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    font-weight: 500;
    color: var(--text-tertiary);
    background: transparent;
    border: none;
    padding: 4px 12px;
    border-radius: 4px;
    cursor: pointer;
    transition: all 0.15s;
    display: flex;
    align-items: center;
    gap: 6px;
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
</style>
