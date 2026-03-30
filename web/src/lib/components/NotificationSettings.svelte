<script lang="ts">
  import type { NotificationConfig } from '../protocol/messages';
  import { toasts } from '../stores/toast.svelte';

  let loading = $state(false);
  let config = $state<NotificationConfig | null>(null);
  let open = $state(false);

  async function loadConfig(): Promise<void> {
    loading = true;
    try {
      const res = await fetch('/api/config/notifications', { credentials: 'include' });
      if (res.ok) {
        config = await res.json() as NotificationConfig;
      } else {
        toasts.error('Failed to load notification settings');
      }
    } catch {
      toasts.error('Failed to load notification settings');
    } finally {
      loading = false;
    }
  }

  async function saveConfig(): Promise<void> {
    if (!config) return;
    loading = true;
    try {
      const res = await fetch('/api/config/notifications', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify(config),
      });
      if (res.ok) {
        config = await res.json() as NotificationConfig;
        toasts.success('Notification settings saved');
      } else {
        const err = await res.json() as { error?: string };
        toasts.error(err.error ?? 'Failed to save settings');
      }
    } catch {
      toasts.error('Failed to save notification settings');
    } finally {
      loading = false;
    }
  }

  function handleToggle(): void {
    if (open) {
      open = false;
    } else {
      open = true;
      void loadConfig();
    }
  }
</script>

<div class="notification-settings">
  <button class="toggle-btn" onclick={handleToggle} title="Notification Settings" aria-label="Notification Settings">
    <span class="gear-icon">&#x2699;</span>
  </button>

  {#if open && config}
    <div class="dropdown">
      <h4 class="dropdown-title">Notification Settings</h4>

      <!-- Quiet Hours -->
      <div class="section">
        <label class="section-label">
          <input
            type="checkbox"
            bind:checked={config.quietHours.enabled}
            onchange={saveConfig}
          />
          Quiet Hours
        </label>
        {#if config.quietHours.enabled}
          <div class="time-row">
            <label class="time-label">
              From
              <input
                type="time"
                bind:value={config.quietHours.start}
                onchange={saveConfig}
                class="time-input"
              />
            </label>
            <label class="time-label">
              To
              <input
                type="time"
                bind:value={config.quietHours.end}
                onchange={saveConfig}
                class="time-input"
              />
            </label>
          </div>
          <p class="hint">Only high-priority notifications fire during quiet hours.</p>
        {/if}
      </div>

      <!-- Priority Threshold -->
      <div class="section">
        <span class="section-label">Priority Threshold</span>
        <div class="threshold-row">
          <label class="threshold-option">
            <input
              type="radio"
              name="threshold"
              value="low"
              checked={config.priorityThreshold === 'low'}
              onchange={() => { config!.priorityThreshold = 'low'; void saveConfig(); }}
            />
            <span class="priority-dot priority-low"></span> All
          </label>
          <label class="threshold-option">
            <input
              type="radio"
              name="threshold"
              value="medium"
              checked={config.priorityThreshold === 'medium'}
              onchange={() => { config!.priorityThreshold = 'medium'; void saveConfig(); }}
            />
            <span class="priority-dot priority-medium"></span> Medium+
          </label>
          <label class="threshold-option">
            <input
              type="radio"
              name="threshold"
              value="high"
              checked={config.priorityThreshold === 'high'}
              onchange={() => { config!.priorityThreshold = 'high'; void saveConfig(); }}
            />
            <span class="priority-dot priority-high"></span> High only
          </label>
        </div>
      </div>

      <!-- Digest -->
      <div class="section">
        <label class="section-label">
          <input
            type="checkbox"
            bind:checked={config.digest.enabled}
            onchange={saveConfig}
          />
          Digest Mode
        </label>
        {#if config.digest.enabled}
          <div class="digest-row">
            <span class="digest-label">Interval:</span>
            <select
              bind:value={config.digest.intervalMinutes}
              onchange={saveConfig}
              class="digest-select"
            >
              <option value={1}>1 min</option>
              <option value={2}>2 min</option>
              <option value={5}>5 min</option>
              <option value={10}>10 min</option>
              <option value={15}>15 min</option>
            </select>
          </div>
          <p class="hint">Low-priority approvals are batched into a digest notification.</p>
        {/if}
      </div>

      {#if loading}
        <div class="loading-bar">Saving...</div>
      {/if}
    </div>
  {/if}
</div>

<!-- Close dropdown on outside click -->
<!-- svelte-ignore a11y_no_static_element_interactions -->
{#if open}
  <div class="backdrop" onclick={() => { open = false; }} role="presentation"></div>
{/if}

<style>
  .notification-settings {
    position: relative;
    display: inline-block;
  }

  .toggle-btn {
    background: none;
    border: none;
    color: var(--text-secondary);
    cursor: pointer;
    font-size: 1rem;
    padding: 2px 4px;
    transition: color 0.15s;
    line-height: 1;
  }
  .toggle-btn:hover {
    color: var(--accent);
  }

  .gear-icon {
    font-size: 0.9rem;
  }

  .backdrop {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    z-index: 99;
  }

  .dropdown {
    position: absolute;
    top: 100%;
    right: 0;
    z-index: 100;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-md);
    padding: var(--sp-md);
    min-width: 280px;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.3);
  }

  .dropdown-title {
    font-family: var(--font-mono);
    font-size: 0.8rem;
    font-weight: 600;
    color: var(--text-primary);
    margin: 0 0 var(--sp-md) 0;
    padding-bottom: var(--sp-sm);
    border-bottom: 1px solid var(--border);
  }

  .section {
    margin-bottom: var(--sp-md);
  }

  .section-label {
    display: flex;
    align-items: center;
    gap: var(--sp-xs);
    font-family: var(--font-mono);
    font-size: 0.75rem;
    font-weight: 600;
    color: var(--text-primary);
    cursor: pointer;
    margin-bottom: var(--sp-xs);
  }

  .section-label input[type="checkbox"] {
    accent-color: var(--accent);
  }

  .time-row {
    display: flex;
    gap: var(--sp-md);
    margin-top: var(--sp-xs);
    padding-left: var(--sp-md);
  }

  .time-label {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    color: var(--text-secondary);
    display: flex;
    align-items: center;
    gap: var(--sp-xs);
  }

  .time-input {
    background: var(--surface-hover);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    color: var(--text-primary);
    font-family: var(--font-mono);
    font-size: 0.7rem;
    padding: 2px 6px;
  }

  .threshold-row {
    display: flex;
    gap: var(--sp-md);
    padding-left: var(--sp-md);
    margin-top: var(--sp-xs);
  }

  .threshold-option {
    display: flex;
    align-items: center;
    gap: 4px;
    font-family: var(--font-mono);
    font-size: 0.7rem;
    color: var(--text-secondary);
    cursor: pointer;
  }

  .threshold-option input[type="radio"] {
    accent-color: var(--accent);
    margin: 0;
  }

  .priority-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    display: inline-block;
  }

  .priority-high {
    background: #f87171;
  }

  .priority-medium {
    background: #fbbf24;
  }

  .priority-low {
    background: #4ade80;
  }

  .digest-row {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    padding-left: var(--sp-md);
    margin-top: var(--sp-xs);
  }

  .digest-label {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    color: var(--text-secondary);
  }

  .digest-select {
    background: var(--surface-hover);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    color: var(--text-primary);
    font-family: var(--font-mono);
    font-size: 0.7rem;
    padding: 2px 6px;
  }

  .hint {
    font-family: var(--font-mono);
    font-size: 0.6rem;
    color: var(--text-tertiary);
    margin: var(--sp-xs) 0 0 var(--sp-md);
    line-height: 1.4;
  }

  .loading-bar {
    font-family: var(--font-mono);
    font-size: 0.65rem;
    color: var(--accent);
    text-align: center;
    padding: var(--sp-xs) 0;
  }
</style>
