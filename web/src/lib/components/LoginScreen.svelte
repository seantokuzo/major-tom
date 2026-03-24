<script lang="ts">
  import { onMount } from 'svelte';
  import { relay } from '../stores/relay.svelte';
  import { toasts } from '../stores/toast.svelte';

  let error = $state<string | null>(null);
  let loading = $state(true);
  let googleAvailable = $state(false);
  let buttonContainer: HTMLDivElement;

  // PIN state
  let pinDigits = $state<string[]>(['', '', '', '', '', '']);
  let pinInputs: HTMLInputElement[] = [];
  let pinSubmitting = $state(false);

  async function handleCredentialResponse(response: google.accounts.id.CredentialResponse) {
    error = null;
    const result = await relay.login(response.credential);
    if (result.success) {
      toasts.success('Signed in successfully');
      relay.connect();
    } else {
      error = result.error ?? 'Login failed';
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
      // Check if Google OAuth is configured
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

            if (buttonContainer) {
              google.accounts.id.renderButton(buttonContainer, {
                theme: 'filled_black',
                size: 'large',
                shape: 'rectangular',
              });
            }

            google.accounts.id.prompt();
            googleAvailable = true;
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
      {:else}
        {#if error}
          <p class="error-message">{error}</p>
        {/if}

        <div class="google-btn-container" bind:this={buttonContainer} class:hidden={!googleAvailable}></div>

        {#if googleAvailable}
          <div class="divider">
            <span class="divider-line"></span>
            <span class="divider-text">or enter PIN</span>
            <span class="divider-line"></span>
          </div>
        {:else}
          <p class="status-text">Enter the PIN from server startup</p>
        {/if}

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
</style>
