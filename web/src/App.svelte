<script lang="ts">
  import ConnectionBar from './lib/components/ConnectionBar.svelte';
  import ConnectionStatus from './lib/components/ConnectionStatus.svelte';
  import SessionInfo from './lib/components/SessionInfo.svelte';
  import ChatView from './lib/components/ChatView.svelte';
  import Toast from './lib/components/Toast.svelte';
  import { relay } from './lib/stores/relay.svelte';
  import { toasts } from './lib/stores/toast.svelte';

  // Wire connection state changes to toast notifications
  let prevState = $state(relay.connectionState);

  $effect(() => {
    const state = relay.connectionState;
    if (state === prevState) return;
    const was = prevState;
    prevState = state;

    if (state === 'connected' && was !== 'connecting') {
      // Reconnected (not initial connect)
      toasts.success('Connected to relay');
    } else if (state === 'connected' && was === 'connecting') {
      // Initial connect -- only show if we had previous disconnect
      if (relay.lastDisconnectedAt) {
        toasts.success('Connected to relay');
      }
    } else if (state === 'reconnecting' && was === 'connected') {
      toasts.warning('Connection lost, reconnecting...');
    } else if (state === 'disconnected' && relay.connectionError) {
      toasts.error(relay.connectionError);
    }
  });
</script>

<div class="app">
  <header class="header">
    <h1 class="title">Major Tom</h1>
  </header>
  <ConnectionBar />
  <ConnectionStatus />
  <SessionInfo />
  <ChatView />
  <Toast />
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
  }

  .title {
    font-family: var(--font-mono);
    font-size: 0.85rem;
    font-weight: 700;
    color: var(--accent);
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }
</style>
