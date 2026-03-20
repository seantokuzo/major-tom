<script lang="ts">
  import { toasts } from '../stores/toast.svelte';

  const typeColors: Record<string, string> = {
    info: 'var(--skip)',
    success: 'var(--allow)',
    warning: 'var(--accent)',
    error: 'var(--deny)',
  };
</script>

{#if toasts.toasts.length > 0}
  <div class="toast-container" aria-live="polite" role="status">
    {#each toasts.toasts as toast (toast.id)}
      <div
        class="toast toast-{toast.type}"
        style="border-left-color: {typeColors[toast.type]}"
      >
        <span class="toast-dot" style="background: {typeColors[toast.type]}"></span>
        <span class="toast-message">{toast.message}</span>
        <button
          class="toast-dismiss"
          type="button"
          aria-label="Dismiss notification"
          onclick={() => toasts.removeToast(toast.id)}
        >
          &times;
        </button>
      </div>
    {/each}
  </div>
{/if}

<style>
  .toast-container {
    position: fixed;
    bottom: 80px;
    right: 16px;
    z-index: 1000;
    display: flex;
    flex-direction: column-reverse;
    gap: 8px;
    pointer-events: none;
    max-width: 400px;
  }

  @media (max-width: 600px) {
    .toast-container {
      top: 8px;
      bottom: auto;
      left: 8px;
      right: 8px;
      max-width: none;
      flex-direction: column;
      align-items: stretch;
    }
  }

  .toast {
    pointer-events: auto;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 10px 14px;
    background: var(--surface);
    border: 1px solid var(--border);
    border-left: 3px solid;
    border-radius: var(--r-sm);
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.4);
    animation: toast-slide-in 0.25s ease-out;
    min-width: 260px;
  }

  @keyframes toast-slide-in {
    from {
      opacity: 0;
      transform: translateY(12px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  @media (max-width: 600px) {
    @keyframes toast-slide-in {
      from {
        opacity: 0;
        transform: translateY(-12px);
      }
      to {
        opacity: 1;
        transform: translateY(0);
      }
    }
  }

  .toast-dot {
    width: 6px;
    height: 6px;
    border-radius: var(--r-full);
    flex-shrink: 0;
  }

  .toast-message {
    flex: 1;
    font-family: var(--font-mono);
    font-size: 0.8rem;
    color: var(--text-primary);
    line-height: 1.4;
  }

  .toast-dismiss {
    background: none;
    border: none;
    color: var(--text-tertiary);
    font-size: 1.1rem;
    cursor: pointer;
    padding: 0 2px;
    line-height: 1;
    flex-shrink: 0;
  }
  .toast-dismiss:hover {
    color: var(--text-primary);
  }
</style>
