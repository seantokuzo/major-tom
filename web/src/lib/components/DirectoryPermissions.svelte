<script lang="ts">
  import { relay } from '../stores/relay.svelte';

  let { userId, userRole }: { userId: string; userRole?: string } = $props();

  let newPath = $state('');
  let paths = $derived(relay.userSandboxPaths.get(userId) ?? []);

  $effect(() => {
    if (userId && relay.isConnected) {
      relay.getUserSandboxPaths(userId);
    }
  });

  function addPath() {
    const trimmed = newPath.trim();
    if (!trimmed) return;
    const updated = [...paths, trimmed];
    relay.setUserSandboxPaths(userId, updated);
    newPath = '';
  }

  function removePath(index: number) {
    const updated = paths.filter((_, i) => i !== index);
    relay.setUserSandboxPaths(userId, updated);
  }

  function clearAll() {
    relay.clearUserSandboxPaths(userId);
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter') {
      e.preventDefault();
      addPath();
    }
  }
</script>

<div class="dir-perms">
  <div class="dir-perms-header">
    <h4 class="dir-perms-title">Directory Access</h4>
    {#if paths.length === 0}
      {#if userRole && userRole !== 'admin'}
        <span class="badge badge-no-access">No access</span>
      {:else}
        <span class="badge badge-unrestricted">Unrestricted</span>
      {/if}
    {:else}
      <span class="badge badge-restricted">{paths.length} path{paths.length !== 1 ? 's' : ''}</span>
    {/if}
  </div>

  {#if paths.length > 0}
    <div class="path-list">
      {#each paths as path, i}
        <div class="path-item">
          <span class="path-index">{i + 1}.</span>
          <span class="path-text">{path}</span>
          <button
            class="btn-remove"
            onclick={() => removePath(i)}
            title="Remove path"
          >&times;</button>
        </div>
      {/each}
    </div>
  {/if}

  <div class="input-row">
    <input
      type="text"
      class="path-input"
      bind:value={newPath}
      onkeydown={handleKeydown}
      placeholder="/path/to/directory"
    />
    <button
      class="btn-add"
      onclick={addPath}
      disabled={!newPath.trim()}
    >Add</button>
  </div>

  {#if paths.length > 0}
    <button class="btn-clear" onclick={clearAll}>
      {userRole && userRole !== 'admin' ? 'Remove All Access' : 'Clear Restrictions'}
    </button>
  {/if}
</div>

<style>
  .dir-perms {
    display: flex;
    flex-direction: column;
    gap: var(--sp-sm);
    padding: var(--sp-md);
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
  }

  .dir-perms-header {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
  }

  .dir-perms-title {
    font-family: var(--font-mono);
    font-size: 0.8rem;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
  }

  .badge {
    padding: 1px 8px;
    border-radius: var(--r-full);
    font-family: var(--font-mono);
    font-size: 0.55rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .badge-unrestricted {
    background: var(--allow);
    color: #000;
  }

  .badge-no-access {
    background: var(--text-tertiary);
    color: #000;
  }

  .badge-restricted {
    background: var(--deny);
    color: #fff;
  }

  .path-list {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .path-item {
    display: flex;
    align-items: center;
    gap: var(--sp-xs);
    padding: 3px var(--sp-sm);
    background: var(--bg);
    border-radius: var(--r-sm);
  }

  .path-index {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    color: var(--text-tertiary);
    min-width: 1.5em;
  }

  .path-text {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    color: var(--text-primary);
    flex: 1;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .btn-remove {
    background: transparent;
    border: none;
    color: var(--deny);
    font-size: 1rem;
    line-height: 1;
    cursor: pointer;
    padding: 0 4px;
    opacity: 0.6;
    transition: opacity 0.15s;
  }

  .btn-remove:hover {
    opacity: 1;
  }

  .input-row {
    display: flex;
    gap: var(--sp-xs);
  }

  .path-input {
    flex: 1;
    padding: 4px 8px;
    background: var(--bg);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    color: var(--text-primary);
    font-family: var(--font-mono);
    font-size: 0.75rem;
    outline: none;
    transition: border-color 0.15s;
  }

  .path-input:focus {
    border-color: var(--accent);
  }

  .path-input::placeholder {
    color: var(--text-tertiary);
  }

  .btn-add {
    padding: 4px 12px;
    background: var(--accent);
    color: #000;
    border: none;
    border-radius: var(--r-sm);
    font-family: var(--font-mono);
    font-size: 0.7rem;
    font-weight: 600;
    cursor: pointer;
    transition: opacity 0.15s;
  }

  .btn-add:hover:not(:disabled) {
    opacity: 0.85;
  }

  .btn-add:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .btn-clear {
    align-self: flex-start;
    padding: 3px 10px;
    background: transparent;
    border: 1px solid var(--deny);
    border-radius: var(--r-sm);
    color: var(--deny);
    font-family: var(--font-mono);
    font-size: 0.65rem;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.15s;
  }

  .btn-clear:hover {
    background: var(--deny);
    color: #fff;
  }
</style>
