<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import { templates } from '../stores/templates.svelte';

  interface Command {
    name: string;
    description: string;
    action: () => void;
  }

  let {
    open = $bindable(false),
    onClose,
    onOpenTemplates,
    onOpenSaveTemplate,
  }: {
    open: boolean;
    onClose: () => void;
    onOpenTemplates?: () => void;
    onOpenSaveTemplate?: () => void;
  } = $props();

  let searchText = $state('');
  let selectedIndex = $state(0);
  let inputEl = $state<HTMLInputElement | undefined>(undefined);

  const commands: Command[] = [
    {
      name: '/new',
      description: 'Start a fresh session',
      action: () => {
        relay.trackCommandUsage('/new');
        relay.newSession();
      },
    },
    {
      name: '/clear',
      description: 'Clear chat display (keep session)',
      action: () => {
        relay.trackCommandUsage('/clear');
        relay.clearMessages();
      },
    },
    {
      name: '/plan',
      description: 'Enter plan mode',
      action: () => {
        relay.trackCommandUsage('/plan');
        relay.sendPrompt('Please enter plan mode');
      },
    },
    {
      name: '/compact',
      description: 'Compact context window',
      action: () => {
        relay.trackCommandUsage('/compact');
        relay.sendPrompt('/compact');
      },
    },
    {
      name: '/model sonnet',
      description: 'Switch to Sonnet',
      action: () => {
        relay.trackCommandUsage('/model sonnet');
        relay.sendPrompt('/model sonnet');
      },
    },
    {
      name: '/model opus',
      description: 'Switch to Opus',
      action: () => {
        relay.trackCommandUsage('/model opus');
        relay.sendPrompt('/model opus');
      },
    },
    {
      name: '/model haiku',
      description: 'Switch to Haiku',
      action: () => {
        relay.trackCommandUsage('/model haiku');
        relay.sendPrompt('/model haiku');
      },
    },
    {
      name: '/btw',
      description: 'Quick side-question (won\'t derail Claude)',
      action: () => {
        relay.trackCommandUsage('/btw');
        relay.inputPrefix = "Quick question, don't lose track of what you're working on: ";
        // Close palette and let user type their question
      },
    },
    {
      name: '/save',
      description: 'Save current input as a template',
      action: () => {
        relay.trackCommandUsage('/save');
        onOpenSaveTemplate?.();
      },
    },
    {
      name: '/templates',
      description: 'Browse saved prompt templates',
      action: () => {
        relay.trackCommandUsage('/templates');
        onOpenTemplates?.();
      },
    },
  ];

  let filteredCommands = $derived.by(() => {
    const usage = relay.getCommandUsage();
    const query = searchText.toLowerCase().replace(/^\//, '');

    let filtered = commands;
    if (query) {
      filtered = commands.filter(
        (c) =>
          c.name.toLowerCase().includes(query) ||
          c.description.toLowerCase().includes(query)
      );
    }

    // Sort by usage count (descending), then alphabetically
    const sorted = [...filtered].sort((a, b) => {
      const aCount = usage[a.name] || 0;
      const bCount = usage[b.name] || 0;
      if (bCount !== aCount) return bCount - aCount;
      return a.name.localeCompare(b.name);
    });

    // Append matching templates when user has typed a query
    if (query) {
      const matchingTemplates = templates.search(query).slice(0, 5);
      for (const tpl of matchingTemplates) {
        sorted.push({
          name: `# ${tpl.name}`,
          description: tpl.content.length > 50 ? tpl.content.slice(0, 50) + '...' : tpl.content,
          action: () => {
            const used = templates.use(tpl.id);
            if (used) {
              relay.inputText = used.content;
            }
          },
        });
      }
    }

    return sorted;
  });

  function selectCommand(cmd: Command) {
    cmd.action();
    close();
  }

  function close() {
    searchText = '';
    selectedIndex = 0;
    open = false;
    onClose();
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') {
      e.preventDefault();
      close();
      return;
    }
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      if (filteredCommands.length > 0) {
        selectedIndex = Math.min(selectedIndex + 1, filteredCommands.length - 1);
      }
      return;
    }
    if (e.key === 'ArrowUp') {
      e.preventDefault();
      if (filteredCommands.length > 0) {
        selectedIndex = Math.max(selectedIndex - 1, 0);
      }
      return;
    }
    if (e.key === 'Enter') {
      e.preventDefault();
      const cmd = filteredCommands[selectedIndex];
      if (cmd) selectCommand(cmd);
      return;
    }
  }

  function handlePaletteKeydown(e: KeyboardEvent) {
    // Only stop propagation for keys we handle — let Escape bubble through
    if (['ArrowDown', 'ArrowUp', 'Enter'].includes(e.key)) {
      e.stopPropagation();
    }
  }

  // Reset selection when filter changes
  $effect(() => {
    filteredCommands.length;
    selectedIndex = 0;
  });

  // Focus input when opened
  $effect(() => {
    if (open) {
      queueMicrotask(() => inputEl?.focus());
    }
  });
</script>

{#if open}
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="palette-backdrop" onclick={close} onkeydown={handleKeydown} role="presentation">
    <div class="palette" onclick={(e) => e.stopPropagation()} onkeydown={handlePaletteKeydown} role="dialog" aria-label="Command palette" aria-modal="true">
      <div class="palette-input-row">
        <span class="palette-prompt">/</span>
        <input
          bind:this={inputEl}
          bind:value={searchText}
          class="palette-input"
          placeholder="Type a command..."
          onkeydown={handleKeydown}
        />
      </div>
      <div class="palette-list">
        {#each filteredCommands as cmd, i (cmd.name)}
          <button
            class="palette-item"
            class:selected={i === selectedIndex}
            onclick={() => selectCommand(cmd)}
            onmouseenter={() => selectedIndex = i}
          >
            <span class="cmd-name">{cmd.name}</span>
            <span class="cmd-desc">{cmd.description}</span>
          </button>
        {/each}
        {#if filteredCommands.length === 0}
          <div class="palette-empty">No matching commands</div>
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .palette-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.5);
    display: flex;
    align-items: flex-start;
    justify-content: center;
    padding-top: 20vh;
    z-index: 100;
  }

  .palette {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-md);
    width: 90%;
    max-width: 420px;
    overflow: hidden;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5);
  }

  .palette-input-row {
    display: flex;
    align-items: center;
    padding: var(--sp-md) var(--sp-lg);
    border-bottom: 1px solid var(--border);
  }

  .palette-prompt {
    font-family: var(--font-mono);
    font-size: 0.95rem;
    color: var(--accent);
    margin-right: var(--sp-xs);
  }

  .palette-input {
    flex: 1;
    background: transparent;
    border: none;
    outline: none;
    color: var(--text-primary);
    font-family: var(--font-mono);
    font-size: 0.9rem;
  }
  .palette-input::placeholder {
    color: var(--text-tertiary);
  }

  .palette-list {
    max-height: 300px;
    overflow-y: auto;
  }

  .palette-item {
    display: flex;
    align-items: center;
    gap: var(--sp-md);
    width: 100%;
    padding: var(--sp-sm) var(--sp-lg);
    background: transparent;
    border: none;
    cursor: pointer;
    text-align: left;
    color: var(--text-primary);
    transition: background 0.1s;
  }

  .palette-item.selected,
  .palette-item:hover {
    background: var(--surface-hover);
  }

  .cmd-name {
    font-family: var(--font-mono);
    font-size: 0.85rem;
    font-weight: 600;
    color: var(--accent);
    white-space: nowrap;
    min-width: 110px;
  }

  .cmd-desc {
    font-size: 0.8rem;
    color: var(--text-secondary);
  }

  .palette-empty {
    padding: var(--sp-lg);
    text-align: center;
    font-size: 0.8rem;
    color: var(--text-tertiary);
  }
</style>
