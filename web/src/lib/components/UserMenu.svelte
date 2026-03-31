<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import { presenceStore } from '../stores/presence.svelte';
  import DirectoryPermissions from './DirectoryPermissions.svelte';

  import { onMount } from 'svelte';

  let open = $state(false);
  let expandedUserId = $state<string | null>(null);

  function toggleMenu() {
    open = !open;
  }

  function closeMenu() {
    open = false;
  }

  function handleLogout() {
    open = false;
    relay.logout();
  }

  function handleBackdropKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      closeMenu();
    }
  }

  // Close on Escape
  onMount(() => {
    function onKeydown(e: KeyboardEvent) {
      if (e.key === 'Escape' && open) closeMenu();
    }
    window.addEventListener('keydown', onKeydown);
    return () => window.removeEventListener('keydown', onKeydown);
  });

  const multiUser = $derived(relay.multiUserEnabled);

  const roleBadgeColor: Record<string, string> = {
    admin: 'var(--accent)',
    operator: 'var(--allow)',
    viewer: 'var(--text-tertiary)',
  };
</script>

{#if relay.user}
  <div class="user-menu-wrapper">
    <button class="user-trigger" onclick={toggleMenu} title={relay.user.email} aria-expanded={open} aria-haspopup="true">
      {#if relay.user.picture}
        <img class="user-avatar" src={relay.user.picture} alt="" />
      {:else}
        <span class="user-avatar-fallback">
          {relay.user.email[0].toUpperCase()}
        </span>
      {/if}
      {#if multiUser && presenceStore.onlineCount > 1}
        <span class="online-badge">{presenceStore.onlineCount}</span>
      {/if}
    </button>

    {#if open}
      <div
        class="backdrop"
        role="button"
        tabindex="0"
        aria-label="Close menu"
        onclick={closeMenu}
        onkeydown={handleBackdropKeydown}
      ></div>
      <div class="user-dropdown">
        <div class="user-info">
          <span class="user-name">{relay.user.name ?? relay.user.email}</span>
          <span class="user-email">{relay.user.email}</span>
          {#if multiUser && relay.user.role}
            <span
              class="role-badge"
              style="background: {roleBadgeColor[relay.user.role] ?? 'var(--text-tertiary)'}"
            >
              {relay.user.role}
            </span>
          {/if}
        </div>
        {#if multiUser}
          <div class="online-section">
            <span class="online-label">{presenceStore.onlineCount} online</span>
          </div>
          {#if relay.isAdmin && presenceStore.onlineCount > 0}
            <div class="team-section">
              <span class="team-label">Directory Access</span>
              {#each presenceStore.onlineUsers as user (user.userId)}
                <div class="team-user-entry">
                  <button
                    class="team-user-row"
                    onclick={() => expandedUserId = expandedUserId === user.userId ? null : user.userId}
                  >
                    <span class="team-user-name">{user.name ?? user.email}</span>
                    <span class="team-user-role" style="color: {roleBadgeColor[user.role] ?? 'var(--text-tertiary)'}">{user.role}</span>
                    <span class="expand-arrow">{expandedUserId === user.userId ? '▴' : '▾'}</span>
                  </button>
                  {#if expandedUserId === user.userId}
                    <div class="dir-perms-wrapper">
                      <DirectoryPermissions userId={user.userId} />
                    </div>
                  {/if}
                </div>
              {/each}
            </div>
          {/if}
        {/if}
        <button class="menu-item" onclick={handleLogout}>Sign out</button>
      </div>
    {/if}
  </div>
{/if}

<style>
  .user-menu-wrapper {
    position: relative;
  }

  .user-trigger {
    position: relative;
    background: transparent;
    border: 1px solid var(--border);
    border-radius: var(--r-full);
    cursor: pointer;
    padding: 0;
    width: 28px;
    height: 28px;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: border-color 0.15s;
    overflow: visible;
  }

  .user-trigger:hover {
    border-color: var(--accent);
  }

  .user-avatar {
    width: 24px;
    height: 24px;
    border-radius: 50%;
    object-fit: cover;
  }

  .user-avatar-fallback {
    width: 24px;
    height: 24px;
    border-radius: 50%;
    background: var(--surface-hover);
    color: var(--text-secondary);
    font-family: var(--font-mono);
    font-size: 0.65rem;
    font-weight: 700;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .online-badge {
    position: absolute;
    top: -4px;
    right: -4px;
    min-width: 16px;
    height: 16px;
    border-radius: var(--r-full);
    background: var(--allow);
    color: #000;
    font-family: var(--font-mono);
    font-size: 0.5rem;
    font-weight: 700;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0 3px;
    border: 2px solid var(--bg);
  }

  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 50;
  }

  .user-dropdown {
    position: absolute;
    top: calc(100% + 6px);
    right: 0;
    z-index: 51;
    min-width: 180px;
    max-width: 340px;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-md);
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.5);
    overflow: hidden;
  }

  .user-info {
    padding: var(--sp-md);
    border-bottom: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    gap: var(--sp-xs);
  }

  .user-name {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    font-weight: 600;
    color: var(--text-primary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .user-email {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    color: var(--text-tertiary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .role-badge {
    display: inline-block;
    align-self: flex-start;
    padding: 1px 8px;
    border-radius: var(--r-full);
    font-family: var(--font-mono);
    font-size: 0.55rem;
    font-weight: 700;
    color: #000;
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .online-section {
    padding: var(--sp-sm) var(--sp-md);
    border-bottom: 1px solid var(--border);
  }

  .online-label {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    color: var(--allow);
    font-weight: 500;
  }

  .menu-item {
    display: block;
    width: 100%;
    padding: var(--sp-sm) var(--sp-md);
    background: transparent;
    border: none;
    color: var(--text-secondary);
    font-family: var(--font-mono);
    font-size: 0.7rem;
    text-align: left;
    cursor: pointer;
    transition: all 0.15s;
  }

  .menu-item:hover {
    background: var(--surface-hover);
    color: var(--text-primary);
  }

  .team-section {
    border-bottom: 1px solid var(--border);
    padding: var(--sp-sm) 0;
  }

  .team-label {
    display: block;
    padding: 0 var(--sp-md) var(--sp-xs);
    font-family: var(--font-mono);
    font-size: 0.55rem;
    font-weight: 700;
    color: var(--text-tertiary);
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }

  .team-user-entry {
    display: flex;
    flex-direction: column;
  }

  .team-user-row {
    display: flex;
    align-items: center;
    gap: var(--sp-xs);
    width: 100%;
    padding: var(--sp-xs) var(--sp-md);
    background: transparent;
    border: none;
    cursor: pointer;
    transition: background 0.15s;
  }

  .team-user-row:hover {
    background: var(--surface-hover);
  }

  .team-user-name {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    color: var(--text-primary);
    flex: 1;
    text-align: left;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .team-user-role {
    font-family: var(--font-mono);
    font-size: 0.5rem;
    font-weight: 600;
    text-transform: uppercase;
  }

  .expand-arrow {
    font-size: 0.6rem;
    color: var(--text-tertiary);
  }

  .dir-perms-wrapper {
    padding: 0 var(--sp-xs) var(--sp-xs);
  }
</style>
