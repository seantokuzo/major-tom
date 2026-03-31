<script lang="ts">
  import type { UserPresence } from '../stores/presence.svelte';

  interface Props {
    users: UserPresence[];
    maxShow?: number;
    size?: 'sm' | 'md';
  }

  let { users, maxShow = 3, size = 'sm' }: Props = $props();

  const visible = $derived(users.slice(0, maxShow));
  const overflow = $derived(Math.max(0, users.length - maxShow));

  function getInitials(user: UserPresence): string {
    if (user.name) {
      return user.name.split(' ').map(w => w[0]).join('').slice(0, 2).toUpperCase();
    }
    return user.email[0].toUpperCase();
  }

  function getColor(userId: string): string {
    let hash = 0;
    for (let i = 0; i < userId.length; i++) {
      hash = userId.charCodeAt(i) + ((hash << 5) - hash);
    }
    const hue = Math.abs(hash) % 360;
    return `hsl(${hue}, 60%, 45%)`;
  }
</script>

<div class="avatar-stack" class:sm={size === 'sm'} class:md={size === 'md'}>
  {#each visible as user (user.userId)}
    {#if user.picture}
      <img
        class="avatar"
        src={user.picture}
        alt={user.name ?? user.email}
        title={user.name ?? user.email}
      />
    {:else}
      <span
        class="avatar initials"
        style="background: {getColor(user.userId)}"
        title={user.name ?? user.email}
      >
        {getInitials(user)}
      </span>
    {/if}
  {/each}
  {#if overflow > 0}
    <span class="avatar overflow-badge">+{overflow}</span>
  {/if}
</div>

<style>
  .avatar-stack {
    display: flex;
    align-items: center;
    flex-shrink: 0;
  }

  .avatar-stack.sm {
    --avatar-size: 24px;
    --avatar-font: 0.55rem;
    --avatar-overlap: -6px;
  }

  .avatar-stack.md {
    --avatar-size: 32px;
    --avatar-font: 0.65rem;
    --avatar-overlap: -8px;
  }

  .avatar {
    width: var(--avatar-size);
    height: var(--avatar-size);
    border-radius: 50%;
    border: 2px solid var(--bg);
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    font-family: var(--font-mono);
    font-size: var(--avatar-font);
    font-weight: 700;
    color: #fff;
    object-fit: cover;
  }

  .avatar + .avatar {
    margin-left: var(--avatar-overlap);
  }

  .avatar.initials {
    user-select: none;
  }

  .avatar.overflow-badge {
    background: var(--surface-hover);
    color: var(--text-secondary);
    font-size: var(--avatar-font);
    border-color: var(--border);
  }
</style>
