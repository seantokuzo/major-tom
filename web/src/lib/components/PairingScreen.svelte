<script lang="ts">
  import { onDestroy } from 'svelte';
  import { relay } from '../stores/relay.svelte';
  import { toasts } from '../stores/toast.svelte';

  let digits = $state<string[]>(['', '', '', '', '', '']);
  let inputRefs = $state<HTMLInputElement[]>([]);
  let error = $state<string | null>(null);
  let loading = $state(false);
  let showManualEntry = $state(false);
  let manualToken = $state('');
  let retryAfter = $state(0);
  let retryInterval: ReturnType<typeof setInterval> | null = null;
  let shaking = $state(false);
  let generatedPin = $state<string | null>(null);
  let generating = $state(false);
  let pinExpiryTimer: ReturnType<typeof setTimeout> | null = null;

  onDestroy(() => {
    if (retryInterval) clearInterval(retryInterval);
    if (pinExpiryTimer) clearTimeout(pinExpiryTimer);
  });

  let pin = $derived(digits.join(''));
  let pinComplete = $derived(pin.length === 6 && /^\d{6}$/.test(pin));

  function detectDeviceName(): string {
    if (typeof navigator === 'undefined') return 'Unknown Device';
    const ua = navigator.userAgent;
    if (/iPhone/.test(ua)) return 'iPhone Safari';
    if (/iPad/.test(ua)) return 'iPad Safari';
    if (/Android/.test(ua)) return 'Android Browser';
    if (/Mac/.test(ua)) return 'Mac Browser';
    if (/Windows/.test(ua)) return 'Windows Browser';
    return 'Web Browser';
  }

  function focusInput(index: number) {
    inputRefs[index]?.focus();
  }

  function handleInput(index: number, e: Event) {
    const input = e.target as HTMLInputElement;
    const value = input.value;

    // Only allow digits
    if (value && !/^\d$/.test(value)) {
      input.value = digits[index];
      return;
    }

    digits[index] = value;
    error = null;

    // Auto-advance to next box
    if (value && index < 5) {
      focusInput(index + 1);
    }
  }

  function handleKeydown(index: number, e: KeyboardEvent) {
    if (e.key === 'Backspace') {
      if (!digits[index] && index > 0) {
        // Move to previous box on backspace if current is empty
        focusInput(index - 1);
        digits[index - 1] = '';
      } else {
        digits[index] = '';
      }
      error = null;
    } else if (e.key === 'ArrowLeft' && index > 0) {
      focusInput(index - 1);
    } else if (e.key === 'ArrowRight' && index < 5) {
      focusInput(index + 1);
    } else if (e.key === 'Enter' && pinComplete) {
      handleSubmit();
    }
  }

  function handlePaste(e: ClipboardEvent) {
    e.preventDefault();
    const pasted = e.clipboardData?.getData('text')?.trim() ?? '';
    const digitsOnly = pasted.replace(/\D/g, '').slice(0, 6);

    if (digitsOnly.length > 0) {
      for (let i = 0; i < 6; i++) {
        digits[i] = digitsOnly[i] || '';
      }
      error = null;
      // Focus last filled or the next empty
      const focusIdx = Math.min(digitsOnly.length, 5);
      focusInput(focusIdx);
    }
  }

  function triggerShake() {
    shaking = true;
    setTimeout(() => { shaking = false; }, 500);
  }

  async function handleSubmit() {
    if (!pinComplete || loading) return;

    loading = true;
    error = null;

    try {
      // Normalize to an HTTP(S) origin, stripping any path/query
      let baseUrl: string;
      const addr = relay.serverAddress;
      if (/^wss?:\/\//.test(addr)) {
        // Map ws→http, wss→https then extract origin
        const httpAddr = addr.replace(/^ws(s?):\/\//, (_, s) => `http${s}://`);
        baseUrl = new URL(httpAddr).origin;
      } else if (/^https?:\/\//.test(addr)) {
        baseUrl = new URL(addr).origin;
      } else {
        // Bare host:port — build a full URL so `new URL` can parse it
        baseUrl = new URL(`${window.location.protocol}//${addr}`).origin;
      }
      const res = await fetch(`${baseUrl}/pair`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          pin,
          deviceName: detectDeviceName(),
        }),
      });

      if (res.ok) {
        const data = await res.json();
        relay.setAuthToken(data.token);
        relay.connect();
        toasts.success('Device paired successfully');
      } else if (res.status === 401) {
        error = 'Invalid or expired PIN';
        triggerShake();
        // Clear digits for retry
        digits = ['', '', '', '', '', ''];
        focusInput(0);
      } else if (res.status === 429) {
        const body = await res.json().catch(() => ({}));
        const seconds = body.retryAfter ?? 60;
        retryAfter = seconds;
        error = `Too many attempts, try again in ${seconds} seconds`;
        triggerShake();

        // Count down
        if (retryInterval) clearInterval(retryInterval);
        retryInterval = setInterval(() => {
          retryAfter--;
          if (retryAfter > 0) {
            error = `Too many attempts, try again in ${retryAfter} seconds`;
          } else {
            error = null;
            if (retryInterval) clearInterval(retryInterval);
            retryInterval = null;
          }
        }, 1000);
      } else {
        const body = await res.json().catch(() => ({ error: 'Pairing failed' }));
        error = body.error ?? 'Pairing failed';
        triggerShake();
      }
    } catch (err) {
      error = 'Could not reach relay server';
      triggerShake();
    } finally {
      loading = false;
    }
  }

  async function handleGeneratePin() {
    if (generating) return;
    generating = true;
    error = null;

    try {
      let baseUrl: string;
      const addr = relay.serverAddress;
      if (/^wss?:\/\//.test(addr)) {
        const httpAddr = addr.replace(/^ws(s?):\/\//, (_, s: string) => `http${s}://`);
        baseUrl = new URL(httpAddr).origin;
      } else if (/^https?:\/\//.test(addr)) {
        baseUrl = new URL(addr).origin;
      } else {
        baseUrl = new URL(`${window.location.protocol}//${addr}`).origin;
      }

      const res = await fetch(`${baseUrl}/pair/generate`, { method: 'POST' });

      if (res.ok) {
        const data = await res.json();
        generatedPin = data.pin;

        // Auto-fill the PIN digits
        for (let i = 0; i < 6; i++) {
          digits[i] = data.pin[i] || '';
        }

        // Auto-clear after expiry
        if (pinExpiryTimer) clearTimeout(pinExpiryTimer);
        const expiresIn = new Date(data.expiresAt).getTime() - Date.now();
        pinExpiryTimer = setTimeout(() => {
          generatedPin = null;
        }, expiresIn);
      } else if (res.status === 403) {
        error = 'PIN generation only works from localhost';
      } else {
        error = 'Failed to generate PIN';
      }
    } catch {
      error = 'Could not reach relay server';
    } finally {
      generating = false;
    }
  }

  function handleManualSave() {
    const trimmed = manualToken.trim();
    if (!trimmed) return;
    relay.setAuthToken(trimmed);
    toasts.success('Token saved');
  }

  function handleManualKeydown(e: KeyboardEvent) {
    if (e.key === 'Enter') handleManualSave();
  }

  // Auto-focus first input on mount
  $effect(() => {
    if (!showManualEntry && inputRefs[0]) {
      // Small delay to ensure DOM is ready
      setTimeout(() => focusInput(0), 100);
    }
  });

  function handleFocusTrap(e: KeyboardEvent) {
    if (e.key !== 'Tab') return;
    const overlay = e.currentTarget as HTMLElement;
    const focusable = overlay.querySelectorAll<HTMLElement>(
      'input:not([disabled]), button:not([disabled]), [tabindex]:not([tabindex="-1"])'
    );
    if (focusable.length === 0) return;
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first.focus();
    }
  }
</script>

<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
<div
  class="pairing-overlay"
  role="dialog"
  aria-modal="true"
  aria-label="Device pairing"
  onkeydown={handleFocusTrap}
>
  <div class="pairing-container">
    <div class="branding">
      <h1 class="brand-title">Major Tom</h1>
      <p class="brand-subtitle">Ground Control</p>
    </div>

    {#if !showManualEntry}
      <div class="pairing-form">
        {#if generatedPin}
          <p class="instructions">
            Share this PIN with the device you want to pair
          </p>
          <div class="generated-pin">
            {#each generatedPin.split('') as d}
              <span class="generated-digit">{d}</span>
            {/each}
          </div>
          <button
            class="btn-generate"
            onclick={handleGeneratePin}
            disabled={generating}
          >
            Generate New PIN
          </button>
          <div class="divider">
            <span class="divider-text">or enter a PIN from another device</span>
          </div>
        {:else}
          <button
            class="btn-pair"
            onclick={handleGeneratePin}
            disabled={generating}
          >
            {#if generating}
              Generating...
            {:else}
              Generate Pairing PIN
            {/if}
          </button>
          <div class="divider">
            <span class="divider-text">or enter a PIN</span>
          </div>
        {/if}

        <div class="pin-inputs" class:shake={shaking}>
          {#each digits as digit, i}
            <input
              bind:this={inputRefs[i]}
              class="pin-box"
              type="text"
              inputmode="numeric"
              maxlength="1"
              autocomplete="one-time-code"
              aria-label={`PIN digit ${i + 1}`}
              value={digit}
              oninput={(e) => handleInput(i, e)}
              onkeydown={(e) => handleKeydown(i, e)}
              onpaste={handlePaste}
              disabled={loading}
            />
          {/each}
        </div>

        {#if error}
          <p class="error-message">{error}</p>
        {/if}

        <button
          class="btn-pair"
          onclick={handleSubmit}
          disabled={!pinComplete || loading || retryAfter > 0}
        >
          {#if loading}
            Pairing...
          {:else}
            Pair Device
          {/if}
        </button>

        <button
          class="link-button"
          onclick={() => { showManualEntry = true; }}
        >
          Use token manually
        </button>
      </div>
    {:else}
      <div class="manual-form">
        <p class="instructions">
          Paste your authentication token below
        </p>

        <div class="manual-input-row">
          <input
            class="manual-input"
            type="password"
            placeholder="Paste token here"
            autocomplete="off"
            bind:value={manualToken}
            onkeydown={handleManualKeydown}
          />
        </div>

        <button
          class="btn-pair"
          onclick={handleManualSave}
          disabled={!manualToken.trim()}
        >
          Save Token
        </button>

        <button
          class="link-button"
          onclick={() => { showManualEntry = false; }}
        >
          Back to PIN pairing
        </button>
      </div>
    {/if}
  </div>
</div>

<style>
  .pairing-overlay {
    position: fixed;
    inset: 0;
    z-index: 1000;
    background: var(--bg);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: var(--sp-lg);
  }

  .pairing-container {
    width: 100%;
    max-width: 380px;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--sp-xxl);
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

  .pairing-form,
  .manual-form {
    width: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--sp-xl);
  }

  .instructions {
    font-size: 0.85rem;
    color: var(--text-secondary);
    text-align: center;
    line-height: 1.5;
  }

  .instructions code {
    font-family: var(--font-mono);
    font-size: 0.8rem;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--r-sm);
    padding: 2px 8px;
    color: var(--accent);
  }

  .pin-inputs {
    display: flex;
    gap: var(--sp-sm);
    justify-content: center;
  }

  .pin-box {
    width: 48px;
    height: 56px;
    background: var(--surface);
    border: 2px solid var(--border);
    border-radius: var(--r-md);
    color: var(--text-primary);
    font-family: var(--font-mono);
    font-size: 1.5rem;
    font-weight: 700;
    text-align: center;
    outline: none;
    transition: border-color 0.15s;
    caret-color: var(--accent);
  }

  .pin-box:focus {
    border-color: var(--accent);
  }

  .pin-box:disabled {
    opacity: 0.5;
  }

  .shake {
    animation: shake 0.4s ease-in-out;
  }

  @keyframes shake {
    0%, 100% { transform: translateX(0); }
    20% { transform: translateX(-8px); }
    40% { transform: translateX(8px); }
    60% { transform: translateX(-6px); }
    80% { transform: translateX(6px); }
  }

  .error-message {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    color: var(--deny);
    text-align: center;
  }

  .btn-pair {
    width: 100%;
    padding: 14px;
    background: var(--accent);
    color: #000;
    border: none;
    border-radius: var(--r-md);
    font-family: var(--font-mono);
    font-size: 0.9rem;
    font-weight: 700;
    cursor: pointer;
    transition: opacity 0.15s;
    letter-spacing: 0.05em;
    text-transform: uppercase;
  }

  .btn-pair:hover:not(:disabled) {
    opacity: 0.9;
  }

  .btn-pair:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .link-button {
    background: none;
    border: none;
    color: var(--text-tertiary);
    font-family: var(--font-mono);
    font-size: 0.75rem;
    cursor: pointer;
    text-decoration: underline;
    text-underline-offset: 3px;
    transition: color 0.15s;
  }

  .link-button:hover {
    color: var(--text-secondary);
  }

  .manual-input-row {
    width: 100%;
  }

  .manual-input {
    width: 100%;
    padding: 12px 16px;
    background: var(--surface);
    border: 2px solid var(--border);
    border-radius: var(--r-md);
    color: var(--text-primary);
    font-family: var(--font-mono);
    font-size: 0.85rem;
    outline: none;
    transition: border-color 0.15s;
  }

  .manual-input:focus {
    border-color: var(--accent);
  }

  .manual-input::placeholder {
    color: var(--text-tertiary);
  }

  .generated-pin {
    display: flex;
    gap: var(--sp-sm);
    justify-content: center;
  }

  .generated-digit {
    width: 48px;
    height: 56px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--surface);
    border: 2px solid var(--accent);
    border-radius: var(--r-md);
    color: var(--accent);
    font-family: var(--font-mono);
    font-size: 1.5rem;
    font-weight: 700;
  }

  .btn-generate {
    width: 100%;
    padding: 14px;
    background: var(--surface);
    color: var(--text-secondary);
    border: 1px solid var(--border);
    border-radius: var(--r-md);
    font-family: var(--font-mono);
    font-size: 0.8rem;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.15s;
  }

  .btn-generate:hover:not(:disabled) {
    border-color: var(--text-tertiary);
    color: var(--text-primary);
  }

  .btn-generate:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }

  .divider {
    width: 100%;
    display: flex;
    align-items: center;
    gap: var(--sp-md);
  }

  .divider::before,
  .divider::after {
    content: '';
    flex: 1;
    height: 1px;
    background: var(--border);
  }

  .divider-text {
    font-family: var(--font-mono);
    font-size: 0.7rem;
    color: var(--text-tertiary);
    white-space: nowrap;
  }
</style>
