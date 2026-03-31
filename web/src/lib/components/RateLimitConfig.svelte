<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import { toasts } from '../stores/toast.svelte';
  import { presenceStore } from '../stores/presence.svelte';

  interface Props {
    open: boolean;
    onClose: () => void;
  }

  let { open, onClose }: Props = $props();

  // Editable copies of role limits
  let editRoles = $state<Record<string, { promptsPerMinute: number; approvalsPerMinute: number }>>({});
  let dirty = $state(false);

  // User override form
  let overrideUserId = $state('');
  let overridePrompts = $state<number | null>(null);
  let overrideApprovals = $state<number | null>(null);

  // Fetch config when panel opens
  $effect(() => {
    if (open && relay.isConnected) {
      relay.getRateLimitConfig();
    }
  });

  // Sync relay config into editable state
  $effect(() => {
    const cfg = relay.rateLimitConfig;
    if (cfg) {
      editRoles = Object.fromEntries(
        Object.entries(cfg.roles).map(([role, limits]) => [role, { ...limits }])
      );
      dirty = false;
    }
  });

  // Close on Escape
  $effect(() => {
    if (!open) return;
    function onKeydown(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose();
    }
    window.addEventListener('keydown', onKeydown);
    return () => window.removeEventListener('keydown', onKeydown);
  });

  function handleBackdropKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      onClose();
    }
  }

  function saveRoleLimits() {
    for (const [role, limits] of Object.entries(editRoles)) {
      relay.setRoleRateLimit(role, limits.promptsPerMinute, limits.approvalsPerMinute);
    }
    dirty = false;
    toasts.success('Rate limits updated');
  }

  function addOverride() {
    if (!overrideUserId) return;
    relay.setUserRateLimitOverride(overrideUserId, {
      promptsPerMinute: overridePrompts ?? undefined,
      approvalsPerMinute: overrideApprovals ?? undefined,
    });
    overrideUserId = '';
    overridePrompts = null;
    overrideApprovals = null;
    toasts.success('User override applied');
    // Refresh config
    setTimeout(() => relay.getRateLimitConfig(), 300);
  }

  function removeOverride(userId: string) {
    relay.clearUserRateLimitOverride(userId);
    toasts.success('Override removed');
    setTimeout(() => relay.getRateLimitConfig(), 300);
  }

  function handleRoleChange() {
    dirty = true;
  }

  // Users for the override dropdown
  const availableUsers = $derived(
    presenceStore.users.filter(u => u.role !== 'admin')
  );
</script>

{#if open}
  <div
    class="panel-backdrop"
    role="button"
    tabindex="0"
    aria-label="Close rate limit config"
    onclick={onClose}
    onkeydown={handleBackdropKeydown}
  >
    <!-- svelte-ignore a11y_click_events_have_key_events -->
    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div class="panel" onclick={(e) => e.stopPropagation()}>
      <div class="panel-header">
        <span class="panel-title">Rate Limits</span>
        <button class="panel-close" onclick={onClose} aria-label="Close">&times;</button>
      </div>

      <div class="panel-body">
        {#if !relay.rateLimitConfig}
          <div class="panel-empty">
            <div class="empty-title">Loading...</div>
          </div>
        {:else}
          <!-- Role Limits -->
          <div class="section">
            <div class="section-title">Per-Role Limits</div>
            <div class="role-table">
              <div class="role-header">
                <span class="role-col">Role</span>
                <span class="num-col">Prompts/min</span>
                <span class="num-col">Approvals/min</span>
              </div>
              {#each Object.entries(editRoles) as [role, limits]}
                <div class="role-row">
                  <span class="role-col role-name">{role}</span>
                  <input
                    class="num-input"
                    type="number"
                    min="1"
                    max="1000"
                    bind:value={limits.promptsPerMinute}
                    oninput={handleRoleChange}
                  />
                  <input
                    class="num-input"
                    type="number"
                    min="1"
                    max="1000"
                    bind:value={limits.approvalsPerMinute}
                    oninput={handleRoleChange}
                  />
                </div>
              {/each}
            </div>
            <button class="save-btn" onclick={saveRoleLimits} disabled={!dirty}>
              {dirty ? 'Save Changes' : 'Saved'}
            </button>
          </div>

          <!-- User Overrides -->
          <div class="section">
            <div class="section-title">User Overrides</div>

            {#if relay.rateLimitConfig.userOverrides && Object.keys(relay.rateLimitConfig.userOverrides).length > 0}
              <div class="overrides-list">
                {#each Object.entries(relay.rateLimitConfig.userOverrides) as [userId, override]}
                  <div class="override-row">
                    <span class="override-user" title={userId}>{userId.slice(0, 12)}...</span>
                    <span class="override-limits">
                      {#if override.promptsPerMinute != null}{override.promptsPerMinute}p{/if}
                      {#if override.approvalsPerMinute != null} {override.approvalsPerMinute}a{/if}
                      /min
                    </span>
                    <button class="remove-btn" onclick={() => removeOverride(userId)} title="Remove override">&times;</button>
                  </div>
                {/each}
              </div>
            {:else}
              <div class="no-overrides">No user overrides</div>
            {/if}

            <div class="override-form">
              <div class="form-label">Add override</div>
              {#if availableUsers.length > 0}
                <select class="form-select" bind:value={overrideUserId}>
                  <option value="">Select user</option>
                  {#each availableUsers as user}
                    <option value={user.userId}>{user.email} ({user.role})</option>
                  {/each}
                </select>
              {:else}
                <input
                  class="form-input"
                  type="text"
                  placeholder="User ID"
                  bind:value={overrideUserId}
                />
              {/if}
              <div class="form-row">
                <div class="form-field">
                  <label class="field-label">Prompts/min</label>
                  <input
                    class="num-input"
                    type="number"
                    min="1"
                    max="1000"
                    placeholder="--"
                    bind:value={overridePrompts}
                  />
                </div>
                <div class="form-field">
                  <label class="field-label">Approvals/min</label>
                  <input
                    class="num-input"
                    type="number"
                    min="1"
                    max="1000"
                    placeholder="--"
                    bind:value={overrideApprovals}
                  />
                </div>
                <button class="add-btn" onclick={addOverride} disabled={!overrideUserId}>Add</button>
              </div>
            </div>
          </div>
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .panel-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.45);
    z-index: 200;
  }

  .panel {
    position: fixed;
    top: 0;
    right: 0;
    bottom: 0;
    width: min(400px, 95vw);
    background: var(--bg);
    border-left: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    box-shadow: -4px 0 24px rgba(0, 0, 0, 0.4);
    animation: slide-in-right 0.2s ease-out;
  }

  @keyframes slide-in-right {
    from { transform: translateX(100%); }
    to { transform: translateX(0); }
  }

  .panel-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: var(--sp-md) var(--sp-lg);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
  }

  .panel-title {
    font-family: var(--font-mono);
    font-size: 0.85rem;
    font-weight: 600;
    color: var(--text-primary);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .panel-close {
    background: transparent;
    border: none;
    color: var(--text-secondary);
    font-size: 1.3rem;
    cursor: pointer;
    padding: 0 var(--sp-xs);
    line-height: 1;
  }
  .panel-close:hover {
    color: var(--text-primary);
  }

  .panel-body {
    flex: 1;
    overflow-y: auto;
    padding: var(--sp-md);
  }

  .panel-empty {
    padding: var(--sp-xl);
    text-align: center;
  }

  .empty-title {
    font-family: var(--font-mono);
    font-size: 0.85rem;
    font-weight: 600;
    color: var(--text-secondary);
  }

  .section {
    margin-bottom: var(--sp-lg);
  }

  .section-title {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    font-weight: 700;
    color: var(--text-primary);
    text-transform: uppercase;
    letter-spacing: 0.04em;
    margin-bottom: var(--sp-sm);
    padding-bottom: var(--sp-xs);
    border-bottom: 1px solid var(--border);
  }

  .role-table {
    margin-bottom: var(--sp-sm);
  }

  .role-header {
    display: flex;
    gap: var(--sp-sm);
    padding: var(--sp-xs) 0;
    border-bottom: 1px solid var(--border);
  }

  .role-header span {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    font-weight: 600;
    color: var(--text-tertiary);
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .role-col {
    flex: 1;
    min-width: 70px;
  }

  .num-col {
    width: 90px;
    text-align: center;
  }

  .role-row {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    padding: var(--sp-xs) 0;
    border-bottom: 1px solid rgba(255, 255, 255, 0.03);
  }

  .role-name {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    font-weight: 600;
    color: var(--text-secondary);
    text-transform: capitalize;
  }

  .num-input {
    width: 90px;
    font-family: var(--font-mono);
    font-size: 0.7rem;
    padding: 4px 8px;
    background: var(--surface);
    color: var(--text-primary);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    text-align: center;
  }
  .num-input:focus {
    border-color: var(--accent);
    outline: none;
  }

  .save-btn {
    width: 100%;
    padding: 6px;
    font-family: var(--font-mono);
    font-size: 0.7rem;
    font-weight: 600;
    color: var(--bg);
    background: var(--accent);
    border: none;
    border-radius: var(--r-sm);
    cursor: pointer;
    transition: all 0.15s;
  }
  .save-btn:hover:not(:disabled) {
    opacity: 0.9;
  }
  .save-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
    background: var(--surface-hover);
    color: var(--text-tertiary);
  }

  .overrides-list {
    margin-bottom: var(--sp-sm);
  }

  .override-row {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    padding: var(--sp-xs) var(--sp-sm);
    border-bottom: 1px solid var(--border);
  }
  .override-row:hover {
    background: var(--surface-hover);
  }

  .override-user {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    color: var(--text-secondary);
    flex: 1;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .override-limits {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    color: var(--accent);
    flex-shrink: 0;
  }

  .remove-btn {
    background: transparent;
    border: none;
    color: var(--deny);
    font-size: 1rem;
    cursor: pointer;
    padding: 0 4px;
    line-height: 1;
    flex-shrink: 0;
  }
  .remove-btn:hover {
    opacity: 0.8;
  }

  .no-overrides {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    color: var(--text-tertiary);
    padding: var(--sp-sm);
    text-align: center;
  }

  .override-form {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-md);
    padding: var(--sp-sm);
  }

  .form-label {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    font-weight: 600;
    color: var(--text-secondary);
    margin-bottom: var(--sp-xs);
  }

  .form-select,
  .form-input {
    width: 100%;
    font-family: var(--font-mono);
    font-size: 0.65rem;
    padding: 4px 6px;
    background: var(--bg);
    color: var(--text-secondary);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    margin-bottom: var(--sp-xs);
  }
  .form-select:focus,
  .form-input:focus {
    border-color: var(--accent);
    outline: none;
  }

  .form-row {
    display: flex;
    gap: var(--sp-xs);
    align-items: flex-end;
  }

  .form-field {
    flex: 1;
  }

  .field-label {
    display: block;
    font-family: var(--font-mono);
    font-size: 0.55rem;
    color: var(--text-tertiary);
    margin-bottom: 2px;
  }

  .add-btn {
    padding: 4px 12px;
    font-family: var(--font-mono);
    font-size: 0.65rem;
    font-weight: 600;
    color: var(--accent);
    background: transparent;
    border: 1px solid var(--accent);
    border-radius: var(--r-sm);
    cursor: pointer;
    transition: all 0.15s;
    flex-shrink: 0;
    height: 26px;
  }
  .add-btn:hover:not(:disabled) {
    background: rgba(77, 217, 115, 0.1);
  }
  .add-btn:disabled {
    opacity: 0.3;
    cursor: not-allowed;
  }
</style>
