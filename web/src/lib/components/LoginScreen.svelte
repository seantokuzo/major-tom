<script lang="ts">
  import { onMount, tick } from 'svelte';
  import { relay } from '../stores/relay.svelte';
  import { toasts } from '../stores/toast.svelte';

  let error = $state<string | null>(null);
  let loading = $state(true);
  let googleAvailable = $state(false);
  let buttonContainer: HTMLDivElement;

  // Derived from relay auth methods — which login options the server supports
  const googleEnabled = $derived(relay.authMethods?.google ?? false);
  const pinEnabled = $derived(relay.authMethods?.pin ?? true); // default true since PIN is always generated
  const noAuthMethods = $derived(relay.authMethods !== null && !googleEnabled && !pinEnabled);

  // PIN state
  let pinDigits = $state<string[]>(['', '', '', '', '', '']);
  let pinInputs = $state<HTMLInputElement[]>([]);
  let pinSubmitting = $state(false);

  // Invite code state
  let inviteCode = $state('');
  let needsInvite = $state(false);
  let pendingCredential = $state<string | null>(null);

  async function handleCredentialResponse(response: google.accounts.id.CredentialResponse) {
    error = null;
    const result = await relay.login(response.credential, needsInvite ? inviteCode.trim().toUpperCase() : undefined);
    if (result.success) {
      needsInvite = false;
      pendingCredential = null;
      inviteCode = '';
      toasts.success('Signed in successfully');
      relay.connect();
    } else if ((result as Record<string, unknown>).code === 'INVITE_REQUIRED' || (result as Record<string, unknown>).inviteRequired === true || result.error?.includes('invite code required')) {
      needsInvite = true;
      pendingCredential = response.credential;
      error = 'Enter your invite code to join';
    } else {
      error = result.error ?? 'Login failed';
    }
  }

  async function submitWithInvite() {
    const normalizedInvite = inviteCode.trim().toUpperCase();
    if (!pendingCredential || normalizedInvite.length < 8) return;
    error = null;
    const result = await relay.login(pendingCredential, normalizedInvite);
    if (result.success) {
      needsInvite = false;
      pendingCredential = null;
      inviteCode = '';
      toasts.success('Signed in successfully');
      relay.connect();
    } else {
      error = result.error ?? 'Invalid invite code';
    }
  }

  async function waitForGsi(timeoutMs = 10_000): Promise<boolean> {
    const start = Date.now();
    while (Date.now() - start < timeoutMs) {
      if (typeof google !== 'undefined' && google?.accounts?.id) return true;
      await new Promise((r) => setTimeout(r, 100));
    }
    return false;
  }

  async function submitPin() {
    const pin = pinDigits.join('');
    if (pin.length !== 6) return;

    pinSubmitting = true;
    error = null;

    const result = await relay.loginWithPin(pin);
    if (result.success) {
      toasts.success('Signed in with PIN');
      relay.connect();
    } else {
      error = result.error ?? 'Invalid PIN';
      // Clear and refocus
      pinDigits = ['', '', '', '', '', ''];
      pinInputs[0]?.focus();
    }
    pinSubmitting = false;
  }

  function handlePinInput(index: number, event: Event) {
    const input = event.target as HTMLInputElement;
    const value = input.value.replace(/\D/g, '');

    if (value.length > 0) {
      pinDigits[index] = value[0];
      // Auto-advance
      if (index < 5) {
        pinInputs[index + 1]?.focus();
      }
      // Auto-submit on last digit
      if (index === 5 && pinDigits.every((d) => d !== '')) {
        submitPin();
      }
    } else {
      pinDigits[index] = '';
    }
  }

  function handlePinKeydown(index: number, event: KeyboardEvent) {
    if (event.key === 'Backspace' && pinDigits[index] === '' && index > 0) {
      pinInputs[index - 1]?.focus();
    }
    if (event.key === 'Enter') {
      submitPin();
    }
  }

  function handlePinPaste(event: ClipboardEvent) {
    event.preventDefault();
    const pasted = (event.clipboardData?.getData('text') ?? '').replace(/\D/g, '').slice(0, 6);
    if (pasted.length === 0) return;

    for (let i = 0; i < 6; i++) {
      pinDigits[i] = pasted[i] ?? '';
    }
    // Focus last filled or submit
    if (pasted.length === 6) {
      submitPin();
    } else {
      pinInputs[pasted.length]?.focus();
    }
  }

  onMount(async () => {
    try {
      // Only attempt Google OAuth if the server reports it as available
      if (!googleEnabled) throw new Error('Google OAuth not enabled');
      const res = await fetch('/auth/google/client-id', { credentials: 'include' });
      if (res.ok) {
        const { clientId } = await res.json();
        if (clientId) {
          const gsiReady = await waitForGsi();
          if (gsiReady) {
            google.accounts.id.initialize({
              client_id: clientId,
              callback: handleCredentialResponse,
              auto_select: true,
              cancel_on_tap_outside: false,
              use_fedcm_for_prompt: false,
            });

            // Mark available and flush DOM so buttonContainer is bound
            // (it lives inside {:else} which needs loading=false to render)
            googleAvailable = true;
            loading = false;
            await tick();

            if (buttonContainer) {
              google.accounts.id.renderButton(buttonContainer, {
                theme: 'filled_black',
                size: 'large',
                shape: 'rectangular',
              });
            }

            google.accounts.id.prompt();
          }
        }
      }
    } catch {
      // Google OAuth not available — PIN-only mode is fine
    }

    loading = false;
    // Auto-focus first PIN input
    pinInputs[0]?.focus();
  });
</script>

<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
<div
  class="login-overlay"
  role="dialog"
  aria-modal="true"
  aria-label="Sign in"
>
  <div class="login-container">
    <div class="branding">
      <h1 class="brand-title">Major Tom</h1>
      <p class="brand-subtitle">Ground Control</p>
    </div>

    <div class="login-form">
      {#if loading}
        <p class="status-text">Loading sign-in...</p>
      {:else if noAuthMethods}
        <!-- Oops screen — no auth methods configured -->
        <div class="oops-screen">
          <div class="oops-scene">
            <div class="oops-sprite"></div>
            <div class="oops-wall"></div>
            <div class="oops-bubble">Hey boss, someone forgot to enable login!</div>
          </div>
          <div class="oops-info">
            <p class="oops-title">No authentication methods enabled</p>
            <div class="oops-hints">
              <p class="oops-hint"><span class="oops-var">GOOGLE_CLIENT_ID</span> in .env to enable Google login</p>
              <p class="oops-hint"><span class="oops-var">AUTH_PIN_ENABLED=true</span> to enable PIN pairing</p>
            </div>
          </div>
        </div>
      {:else}
        {#if error}
          <p class="error-message">{error}</p>
        {/if}

        {#if googleEnabled}
          <div class="google-btn-container" bind:this={buttonContainer} class:hidden={!googleAvailable}></div>
        {/if}

        {#if googleEnabled && pinEnabled}
          <div class="divider">
            <span class="divider-line"></span>
            <span class="divider-text">or enter PIN</span>
            <span class="divider-line"></span>
          </div>
        {:else if pinEnabled && !googleEnabled}
          <p class="status-text">Enter the PIN from server startup</p>
        {/if}

        {#if pinEnabled}
          <!-- PIN input -->
          <div class="pin-row">
            {#each pinDigits as digit, i}
              <input
                bind:this={pinInputs[i]}
                class="pin-digit"
                type="text"
                inputmode="numeric"
                maxlength="1"
                value={digit}
                oninput={(e) => handlePinInput(i, e)}
                onkeydown={(e) => handlePinKeydown(i, e)}
                onpaste={handlePinPaste}
                disabled={pinSubmitting}
                aria-label={`PIN digit ${i + 1}`}
              />
            {/each}
          </div>

          {#if pinSubmitting}
            <p class="status-text">Verifying...</p>
          {/if}
        {/if}

        {#if needsInvite}
          <div class="invite-section">
            <div class="divider">
              <span class="divider-line"></span>
              <span class="divider-text">invite code</span>
              <span class="divider-line"></span>
            </div>
            <p class="status-text">Invite code required to join</p>
            <input
              class="invite-input"
              type="text"
              placeholder="Enter invite code"
              bind:value={inviteCode}
              maxlength="8"
              onkeydown={(e) => { if (e.key === 'Enter') submitWithInvite(); }}
            />
            <button
              class="invite-submit"
              onclick={submitWithInvite}
              disabled={inviteCode.trim().length < 8}
            >
              Join
            </button>
          </div>
        {/if}
      {/if}
    </div>
  </div>
</div>

<style>
  .login-overlay {
    position: fixed;
    inset: 0;
    z-index: 1000;
    background: var(--bg);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--sp-lg);
    padding-top: max(var(--sp-lg), env(safe-area-inset-top));
    padding-bottom: max(var(--sp-lg), env(safe-area-inset-bottom));
    overflow: hidden;
  }

  .login-container {
    width: 100%;
    max-width: 340px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--sp-xl);
  }

  .branding {
    text-align: center;
  }

  .brand-title {
    font-family: var(--font-mono);
    font-size: 1.8rem;
    font-weight: 700;
    color: var(--accent);
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .brand-subtitle {
    font-family: var(--font-mono);
    font-size: 0.85rem;
    color: var(--text-tertiary);
    margin-top: var(--sp-xs);
    letter-spacing: 0.15em;
    text-transform: uppercase;
  }

  .login-form {
    width: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--sp-lg);
  }

  .status-text {
    font-family: var(--font-mono);
    font-size: 0.85rem;
    color: var(--text-tertiary);
    text-align: center;
  }

  .error-message {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    color: var(--deny);
    text-align: center;
  }

  .google-btn-container {
    display: flex;
    justify-content: center;
    min-height: 44px;
  }

  .google-btn-container.hidden {
    display: none;
  }

  .divider {
    display: flex;
    align-items: center;
    gap: var(--sp-sm);
    width: 100%;
  }

  .divider-line {
    flex: 1;
    height: 1px;
    background: var(--border);
  }

  .divider-text {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    color: var(--text-tertiary);
    text-transform: uppercase;
    letter-spacing: 0.1em;
    white-space: nowrap;
  }

  .pin-row {
    display: flex;
    gap: 8px;
    justify-content: center;
  }

  .pin-digit {
    width: 42px;
    height: 52px;
    border: 2px solid var(--border);
    border-radius: 8px;
    background: var(--bg-secondary);
    color: var(--text);
    font-family: var(--font-mono);
    font-size: 1.4rem;
    font-weight: 700;
    text-align: center;
    outline: none;
    transition: border-color 0.15s;
  }

  .pin-digit:focus {
    border-color: var(--accent);
  }

  .pin-digit:disabled {
    opacity: 0.5;
  }

  .invite-section {
    width: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--sp-md);
  }

  .invite-input {
    width: 100%;
    max-width: 260px;
    height: 44px;
    border: 2px solid var(--border);
    border-radius: 8px;
    background: var(--surface);
    color: var(--text-primary);
    font-family: var(--font-mono);
    font-size: 1rem;
    font-weight: 600;
    text-align: center;
    letter-spacing: 0.15em;
    text-transform: uppercase;
    outline: none;
    transition: border-color 0.15s;
  }

  .invite-input:focus {
    border-color: var(--accent);
  }

  .invite-input::placeholder {
    color: var(--text-tertiary);
    letter-spacing: 0.05em;
    text-transform: none;
    font-weight: 400;
  }

  .invite-submit {
    padding: var(--sp-sm) var(--sp-xl);
    font-family: var(--font-mono);
    font-size: 0.8rem;
    font-weight: 600;
    color: var(--bg);
    background: var(--accent);
    border: none;
    border-radius: var(--r-sm);
    cursor: pointer;
    transition: all 0.15s;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .invite-submit:hover:not(:disabled) {
    background: var(--accent-dim);
  }

  .invite-submit:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  /* ── Oops screen — no auth methods ── */

  .oops-screen {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--sp-xl);
    padding: var(--sp-lg) 0;
  }

  .oops-scene {
    position: relative;
    width: 160px;
    height: 80px;
  }

  .oops-sprite {
    position: absolute;
    bottom: 0;
    width: 16px;
    height: 24px;
    background: var(--accent);
    border-radius: 3px 3px 0 0;
    animation: oops-walk 1.6s ease-in-out infinite alternate;
  }

  .oops-sprite::before {
    content: '';
    position: absolute;
    top: -10px;
    left: 2px;
    width: 12px;
    height: 12px;
    background: var(--accent);
    border-radius: 50%;
  }

  .oops-sprite::after {
    content: '';
    position: absolute;
    bottom: 0;
    left: 0;
    width: 16px;
    height: 4px;
    background: var(--accent-dim);
    border-radius: 0 0 2px 2px;
    animation: oops-legs 0.4s steps(2) infinite;
  }

  @keyframes oops-walk {
    0% { left: 10px; }
    45% { left: 120px; }
    55% { left: 120px; }
    100% { left: 10px; }
  }

  @keyframes oops-legs {
    0% { transform: scaleX(1); }
    50% { transform: scaleX(0.6); }
  }

  .oops-wall {
    position: absolute;
    right: 10px;
    bottom: 0;
    width: 8px;
    height: 40px;
    background: var(--border);
    border-radius: 2px;
  }

  .oops-wall::before {
    content: '';
    position: absolute;
    top: 0;
    left: -2px;
    width: 12px;
    height: 4px;
    background: var(--text-tertiary);
    border-radius: 1px;
  }

  .oops-bubble {
    position: absolute;
    top: -4px;
    left: 50%;
    transform: translateX(-50%);
    font-family: var(--font-mono);
    font-size: 0.55rem;
    color: var(--text-secondary);
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 4px 8px;
    white-space: nowrap;
    pointer-events: none;
  }

  .oops-bubble::after {
    content: '';
    position: absolute;
    bottom: -5px;
    left: 50%;
    transform: translateX(-50%);
    width: 0;
    height: 0;
    border-left: 4px solid transparent;
    border-right: 4px solid transparent;
    border-top: 5px solid var(--border);
  }

  .oops-info {
    text-align: center;
    display: flex;
    flex-direction: column;
    gap: var(--sp-md);
  }

  .oops-title {
    font-family: var(--font-mono);
    font-size: 0.8rem;
    font-weight: 600;
    color: var(--text-secondary);
  }

  .oops-hints {
    display: flex;
    flex-direction: column;
    gap: var(--sp-xs);
  }

  .oops-hint {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    color: var(--text-tertiary);
  }

  .oops-var {
    color: var(--accent);
    font-weight: 600;
  }
</style>
