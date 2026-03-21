<script lang="ts">
  import { onDestroy } from 'svelte';
  import { toasts } from '../stores/toast.svelte';
  import { relay as relayStore } from '../stores/relay.svelte';

  // Minimal Web Speech API type declarations (not yet in all TS libs)
  interface SpeechRecognitionResult {
    readonly isFinal: boolean;
    readonly length: number;
    [index: number]: { transcript: string; confidence: number };
  }

  interface SpeechRecognitionResultList {
    readonly length: number;
    [index: number]: SpeechRecognitionResult;
  }

  interface SpeechRecognitionEvent {
    results: SpeechRecognitionResultList;
    resultIndex: number;
  }

  interface SpeechRecognitionErrorEvent {
    error: string;
  }

  type SpeechRecognitionConstructor = new () => {
    continuous: boolean;
    interimResults: boolean;
    lang: string;
    onresult: ((event: SpeechRecognitionEvent) => void) | null;
    onerror: ((event: SpeechRecognitionErrorEvent) => void) | null;
    onend: (() => void) | null;
    start(): void;
    stop(): void;
    abort(): void;
  };

  declare global {
    interface Window {
      SpeechRecognition?: SpeechRecognitionConstructor;
      webkitSpeechRecognition?: SpeechRecognitionConstructor;
    }
  }

  interface Props {
    relay: typeof relayStore;
    disabled?: boolean;
  }

  let { relay, disabled = false }: Props = $props();

  // Feature detection
  const SpeechRecognition =
    typeof window !== 'undefined'
      ? window.SpeechRecognition || window.webkitSpeechRecognition
      : null;

  let supported = $derived(SpeechRecognition != null);
  let recording = $state(false);
  let recognition: InstanceType<SpeechRecognitionConstructor> | null = null;

  function toggle() {
    if (recording) {
      stop();
    } else {
      start();
    }
  }

  function start() {
    if (!SpeechRecognition) return;

    recognition = new SpeechRecognition();
    recognition.continuous = false;
    recognition.interimResults = true;
    recognition.lang = 'en-US';

    // Capture whatever was in the input before we started.
    // Note: the input is effectively locked during recording — any manual edits
    // will be overwritten by speech results. This is acceptable UX since the
    // mic button visually indicates active recording.
    const preExistingText = relay.inputText;

    recognition.onresult = (event: SpeechRecognitionEvent) => {
      let interim = '';
      let final = '';

      for (let i = 0; i < event.results.length; i++) {
        const result = event.results[i];
        if (result.isFinal) {
          final += result[0].transcript;
        } else {
          interim += result[0].transcript;
        }
      }

      // Compose final + interim so interim continues updating after
      // the first finalized segment
      const combined = final + interim;
      if (combined) {
        relay.inputText = preExistingText ? `${preExistingText} ${combined}` : combined;
      }
    };

    recognition.onerror = (event: SpeechRecognitionErrorEvent) => {
      recording = false;
      recognition = null;

      if (event.error === 'no-speech') {
        toasts.info('No speech detected');
      } else if (event.error === 'not-allowed') {
        toasts.error('Microphone access denied');
      } else if (event.error !== 'aborted') {
        toasts.warning(`Speech error: ${event.error}`);
      }
    };

    recognition.onend = () => {
      recording = false;
      recognition = null;
    };

    try {
      recognition.start();
      recording = true;
    } catch {
      toasts.error('Failed to start speech recognition');
      recording = false;
      recognition = null;
    }
  }

  function stop() {
    if (recognition) {
      try {
        recognition.stop();
      } catch {
        // Already stopped
      }
    }
    recording = false;
    recognition = null;
  }

  // Stop recognition on component teardown (e.g., switching tabs)
  onDestroy(() => stop());

  // Stop recognition when disabled prop flips to true
  $effect(() => {
    if (disabled && recording) {
      stop();
    }
  });
</script>

{#if supported}
  <button
    class="mic-btn"
    class:mic-recording={recording}
    type="button"
    aria-label={recording ? 'Stop recording' : 'Voice input'}
    aria-pressed={recording}
    onclick={toggle}
    {disabled}
  >
    <svg
      width="16"
      height="16"
      viewBox="0 0 16 16"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      aria-hidden="true"
    >
      <path
        d="M8 1C6.9 1 6 1.9 6 3v5c0 1.1.9 2 2 2s2-.9 2-2V3c0-1.1-.9-2-2-2z"
        fill="currentColor"
      />
      <path
        d="M12 8a4 4 0 0 1-8 0H3a5 5 0 0 0 4.5 4.97V15h1v-2.03A5 5 0 0 0 13 8h-1z"
        fill="currentColor"
      />
    </svg>
    {#if recording}
      <span class="mic-pulse"></span>
    {/if}
  </button>
{/if}

<style>
  .mic-btn {
    position: relative;
    width: 28px;
    height: 28px;
    border-radius: var(--r-sm);
    border: 1px solid var(--border);
    background: transparent;
    color: var(--text-secondary);
    cursor: pointer;
    transition: all 0.15s;
    flex-shrink: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
  }

  .mic-btn:hover:not(:disabled) {
    color: var(--accent);
    border-color: var(--accent);
  }

  .mic-btn:disabled {
    color: var(--text-tertiary);
    border-color: var(--border);
    cursor: default;
    opacity: 0.4;
  }

  .mic-recording {
    color: var(--deny);
    border-color: var(--deny);
  }

  .mic-recording:hover:not(:disabled) {
    color: var(--deny);
    border-color: var(--deny);
  }

  .mic-pulse {
    position: absolute;
    inset: -3px;
    border-radius: var(--r-sm);
    border: 2px solid var(--deny);
    animation: mic-pulse-anim 1.2s ease-in-out infinite;
    pointer-events: none;
  }

  @keyframes mic-pulse-anim {
    0%,
    100% {
      opacity: 1;
    }
    50% {
      opacity: 0.3;
    }
  }
</style>
