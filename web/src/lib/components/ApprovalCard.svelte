<script lang="ts">
  import type { ApprovalRequest } from '../stores/relay.svelte';
  import type { ApprovalDecision } from '../protocol/messages';

  let { request, onDecision }: {
    request: ApprovalRequest;
    onDecision: (id: string, decision: ApprovalDecision) => void;
  } = $props();
</script>

<div class="card">
  <div class="tool-name">{request.tool}</div>
  <div class="description">{request.description}</div>
  <div class="actions">
    <button class="btn btn-allow" onclick={() => onDecision(request.id, 'allow')}>
      Allow
    </button>
    <button class="btn btn-skip" onclick={() => onDecision(request.id, 'skip')}>
      Skip
    </button>
    <button class="btn btn-deny" onclick={() => onDecision(request.id, 'deny')}>
      Deny
    </button>
  </div>
</div>

<style>
  .card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-md);
    padding: var(--sp-lg);
    min-width: 280px;
    flex-shrink: 0;
  }

  .tool-name {
    font-family: var(--font-mono);
    font-size: 0.85rem;
    font-weight: 600;
    color: var(--accent);
    margin-bottom: var(--sp-xs);
  }

  .description {
    font-size: 0.8rem;
    color: var(--text-secondary);
    margin-bottom: var(--sp-md);
    line-height: 1.4;
    max-height: 60px;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .actions {
    display: flex;
    gap: var(--sp-sm);
  }

  .btn {
    flex: 1;
    padding: var(--sp-sm) var(--sp-md);
    border: none;
    border-radius: var(--r-sm);
    font-size: 0.8rem;
    font-weight: 600;
    cursor: pointer;
    transition: opacity 0.15s;
  }
  .btn:hover { opacity: 0.85; }
  .btn:active { opacity: 0.7; }

  .btn-allow { background: var(--allow); color: #000; }
  .btn-skip { background: var(--skip); color: #000; }
  .btn-deny { background: var(--deny); color: #000; }
</style>
