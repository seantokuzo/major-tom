<script lang="ts">
  import ConnectionBar from './lib/components/ConnectionBar.svelte';
  import ChatView from './lib/components/ChatView.svelte';
</script>

<div class="app">
  <header class="header">
    <h1 class="title">Major Tom</h1>
  </header>
  <ConnectionBar />
  <ChatView />
</div>

<style>
  .app {
    height: 100%;
    display: flex;
    flex-direction: column;
  }

  .header {
    padding: var(--sp-sm) var(--sp-lg);
    background: var(--bg);
    flex-shrink: 0;
  }

  .title {
    font-size: 1rem;
    font-weight: 700;
    color: var(--accent);
    letter-spacing: 0.05em;
  }
</style>
