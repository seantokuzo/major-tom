<script lang="ts">
  import { relay } from '../stores/relay.svelte';
  import { terminalStore } from '../stores/terminal.svelte';

  let outputContainer: HTMLDivElement | undefined;
  let inputEl: HTMLInputElement | undefined;

  // Scroll to bottom when new lines are added
  $effect(() => {
    terminalStore.lines.length;
    if (outputContainer) {
      queueMicrotask(() => {
        outputContainer!.scrollTop = outputContainer!.scrollHeight;
      });
    }
  });

  // Request sandbox root on mount
  $effect(() => {
    if (relay.isConnected && !terminalStore.sandboxRoot) {
      relay.requestFsCwd();
    }
  });

  // ── Command parsing & execution ────────────────────────────

  function executeCommand(raw: string): void {
    const trimmed = raw.trim();
    if (!trimmed) return;

    terminalStore.addToHistory(trimmed);
    terminalStore.addCommand(`${promptPrefix} ${trimmed}`);
    terminalStore.inputText = '';

    // Parse command and args
    const parts = trimmed.split(/\s+/);
    const cmd = parts[0] ?? '';
    const args = parts.slice(1);

    switch (cmd) {
      case 'cd': handleCd(args); break;
      case 'ls': handleLs(args); break;
      case 'cat': handleCat(args); break;
      case 'pwd': handlePwd(); break;
      case 'clear': terminalStore.clear(); break;
      case '/new': case 'claude': handleStartSession(); break;
      case 'help': handleHelp(); break;
      default:
        terminalStore.addError(`Unknown command: ${cmd}. Type 'help' for available commands.`);
    }
  }

  function handleCd(args: string[]): void {
    const target = args[0] ?? '~';
    const resolved = terminalStore.resolvePath(target);
    // Set pending cd target — will be confirmed by fs.ls.response
    terminalStore.pendingCdTarget = resolved;
    terminalStore.isLoading = true;
    terminalStore.lastLsDetailed = false;
    relay.requestFsLs(resolved === '~' ? '.' : resolved.replace(/^~\//, ''));
  }

  function handleLs(args: string[]): void {
    const detailed = args.includes('-la') || args.includes('-l') || args.includes('-al');
    const pathArg = args.find(a => !a.startsWith('-'));
    const target = pathArg ? terminalStore.resolvePath(pathArg) : terminalStore.cwd;

    terminalStore.isLoading = true;
    terminalStore.lastLsDetailed = detailed;
    const requestPath = target === '~' ? '.' : target.replace(/^~\//, '');
    relay.requestFsLs(requestPath);
  }

  function handleCat(args: string[]): void {
    const filePath = args[0];
    if (!filePath) {
      terminalStore.addError('Usage: cat <file>');
      return;
    }
    const resolved = terminalStore.resolvePath(filePath);
    terminalStore.isLoading = true;
    const requestPath = resolved === '~' ? '.' : resolved.replace(/^~\//, '');
    relay.requestFsReadFile(requestPath);
  }

  function handlePwd(): void {
    terminalStore.addOutput(terminalStore.cwd);
  }

  function handleStartSession(): void {
    if (!relay.isConnected) {
      terminalStore.addError('Not connected to relay server');
      return;
    }
    const cwdPath = terminalStore.cwd;
    // Translate sandbox-relative cwd to a path the relay understands:
    // ~ → . (sandbox root), ~/subdir → subdir
    let workingDir: string;
    if (cwdPath === '~') {
      workingDir = '.';
    } else if (cwdPath.startsWith('~/')) {
      workingDir = cwdPath.slice(2);
    } else {
      workingDir = cwdPath;
    }
    terminalStore.addInfo(`Starting Claude session in ${cwdPath}...`);
    relay.startSessionAt(workingDir);
  }

  function handleHelp(): void {
    terminalStore.addOutput(
      'Available commands:\n' +
      '  cd <path>    Change directory\n' +
      '  ls [-la]     List directory contents\n' +
      '  cat <file>   View file contents\n' +
      '  pwd          Print working directory\n' +
      '  clear        Clear terminal\n' +
      '  claude       Start Claude session here\n' +
      '  /new         Start Claude session here\n' +
      '  help         Show this help',
    );
  }

  // ── Input handlers ─────────────────────────────────────────

  function handleKeydown(e: KeyboardEvent): void {
    if (e.key === 'Enter') {
      e.preventDefault();
      executeCommand(terminalStore.inputText);
      return;
    }

    if (e.key === 'ArrowUp') {
      e.preventDefault();
      const result = terminalStore.navigate('up', terminalStore.inputText);
      if (result !== null) terminalStore.inputText = result;
      return;
    }

    if (e.key === 'ArrowDown') {
      e.preventDefault();
      const result = terminalStore.navigate('down', terminalStore.inputText);
      if (result !== null) terminalStore.inputText = result;
      return;
    }
  }

  function handleInput(): void {
    terminalStore.resetNavigation();
  }

  function focusInput(): void {
    inputEl?.focus();
  }

  // ── Display path (shortened for prompt) ────────────────────

  let promptPrefix = $derived.by(() => {
    const cwd = terminalStore.cwd;
    // Show last 2 segments for brevity
    const parts = cwd.split('/');
    if (parts.length <= 2) return `${cwd} $`;
    return `.../${parts.slice(-2).join('/')} $`;
  });
</script>

<!-- svelte-ignore a11y_click_events_have_key_events -->
<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="terminal" onclick={focusInput}>
  <!-- Header with Start Claude Here button -->
  <div class="terminal-header">
    <span class="terminal-title">Terminal</span>
    <span class="terminal-cwd">{terminalStore.cwd}</span>
    <div class="terminal-spacer"></div>
    <button
      class="start-btn"
      onclick={(e) => { e.stopPropagation(); handleStartSession(); }}
      disabled={!relay.isConnected}
      title="Start Claude session in current directory"
    >
      <span class="start-icon">&#9654;</span>
      Start Claude Here
    </button>
  </div>

  <!-- Output area -->
  <div class="terminal-output" bind:this={outputContainer}>
    {#if terminalStore.lines.length === 0}
      <div class="terminal-welcome">
        <span class="welcome-title">Major Tom Terminal</span>
        <span class="welcome-hint">Browse your filesystem and start Claude sessions</span>
        <span class="welcome-hint">Type <code>help</code> for available commands</span>
      </div>
    {/if}
    {#each terminalStore.lines as line (line.id)}
      <div class="terminal-line" class:line-command={line.type === 'command'} class:line-error={line.type === 'error'} class:line-info={line.type === 'info'}>
        <pre class="line-content">{line.content}</pre>
      </div>
    {/each}
    {#if terminalStore.isLoading}
      <div class="terminal-line line-info">
        <pre class="line-content">...</pre>
      </div>
    {/if}
  </div>

  <!-- Input line -->
  <div class="terminal-input-row">
    <span class="prompt">{promptPrefix}</span>
    <input
      bind:this={inputEl}
      bind:value={terminalStore.inputText}
      onkeydown={handleKeydown}
      oninput={handleInput}
      class="terminal-input"
      placeholder="Type a command..."
      disabled={!relay.isConnected}
      spellcheck="false"
      autocomplete="off"
      autocapitalize="off"
    />
  </div>
</div>

<style>
  .terminal {
    flex: 1;
    display: flex;
    flex-direction: column;
    min-height: 0;
    background: var(--bg);
    cursor: text;
  }

  .terminal-header {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    padding: var(--sp-sm) var(--sp-md);
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
  }

  .terminal-title {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    font-weight: 600;
    color: var(--accent);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .terminal-cwd {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    color: var(--text-tertiary);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .terminal-spacer {
    flex: 1;
    min-width: 0;
  }

  .start-btn {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 6px 14px;
    font-family: var(--font-mono);
    font-size: 0.7rem;
    font-weight: 600;
    color: var(--bg);
    background: var(--accent);
    border: 1px solid var(--accent);
    border-radius: var(--r-sm);
    cursor: pointer;
    transition: all 0.15s;
    flex-shrink: 0;
    white-space: nowrap;
  }

  .start-btn:hover:not(:disabled) {
    background: var(--accent-dim);
    border-color: var(--accent-dim);
  }

  .start-btn:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .start-icon {
    font-size: 0.6rem;
  }

  .terminal-output {
    flex: 1;
    overflow-y: auto;
    padding: var(--sp-sm) var(--sp-md);
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-height: 0;
  }

  .terminal-welcome {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--sp-sm);
    padding: var(--sp-xl) 0;
    color: var(--text-tertiary);
  }

  .welcome-title {
    font-family: var(--font-mono);
    font-size: 0.85rem;
    font-weight: 600;
    color: var(--accent);
  }

  .welcome-hint {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    color: var(--text-tertiary);
  }

  .welcome-hint code {
    color: var(--text-secondary);
    background: var(--surface);
    padding: 1px 4px;
    border-radius: 3px;
  }

  .terminal-line {
    padding: 1px 0;
  }

  .line-content {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    line-height: 1.5;
    color: var(--text-primary);
    white-space: pre-wrap;
    word-break: break-word;
    margin: 0;
  }

  .line-command .line-content {
    color: var(--text-secondary);
  }

  .line-error .line-content {
    color: var(--deny);
  }

  .line-info .line-content {
    color: var(--accent);
  }

  .terminal-input-row {
    display: flex;
    align-items: center;
    gap: var(--sp-xs);
    padding: var(--sp-sm) var(--sp-md);
    padding-bottom: max(var(--sp-sm), env(safe-area-inset-bottom));
    background: var(--surface);
    border-top: 1px solid var(--border);
    flex-shrink: 0;
  }

  .prompt {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    color: var(--accent);
    flex-shrink: 0;
    user-select: none;
    white-space: nowrap;
  }

  .terminal-input {
    flex: 1;
    min-width: 0;
    background: transparent;
    border: none;
    outline: none;
    color: var(--text-primary);
    font-family: var(--font-mono);
    font-size: 0.75rem;
    line-height: 1.5;
    caret-color: var(--accent);
  }

  .terminal-input::placeholder {
    color: var(--text-tertiary);
  }

  .terminal-input:disabled {
    opacity: 0.4;
  }
</style>
