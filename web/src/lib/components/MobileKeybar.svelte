<script lang="ts">
  /**
   * Mobile keybar — sits above the iOS keyboard with sticky modifiers
   * (Ctrl, Alt) and one-shot keys (Esc, Tab, arrows, |, ~, /). All keys
   * inject through `inject()` (a passed-in callback that calls
   * `term.input(data, true)` on the underlying xterm) so input flows
   * through xterm.onData like real keystrokes — no raw byte bypass.
   */
  interface Props {
    /** Inject keystrokes into the terminal. Provided by parent. */
    inject: (data: string) => void;
    /** True when the iOS keyboard is visible (parent computes from visualViewport). */
    keyboardVisible: boolean;
  }

  let { inject, keyboardVisible }: Props = $props();

  // Sticky modifier state. Tap once = armed for next key. Long-press = lock.
  let ctrlArmed = $state(false);
  let altArmed = $state(false);
  let ctrlLocked = $state(false);
  let altLocked = $state(false);

  function toggleCtrl(): void {
    if (ctrlLocked) {
      ctrlLocked = false;
      ctrlArmed = false;
    } else {
      ctrlArmed = !ctrlArmed;
    }
  }
  function toggleAlt(): void {
    if (altLocked) {
      altLocked = false;
      altArmed = false;
    } else {
      altArmed = !altArmed;
    }
  }
  function lockCtrl(): void { ctrlLocked = true; ctrlArmed = true; }
  function lockAlt(): void { altLocked = true; altArmed = true; }

  /** Apply armed modifiers to a base character/seq, then disarm (unless locked). */
  function fireKey(base: string, opts: { allowMods?: boolean } = {}): void {
    const allowMods = opts.allowMods !== false;
    let out = base;
    if (allowMods && ctrlArmed) {
      // Ctrl+letter → control byte (1-26). Pass single-char base.
      if (base.length === 1) {
        const code = base.toLowerCase().charCodeAt(0);
        if (code >= 97 && code <= 122) {
          out = String.fromCharCode(code - 96);
        }
      }
    }
    if (allowMods && altArmed) {
      // ESC prefix is the portable Meta encoding xterm.js expects.
      out = '\x1b' + out;
    }
    inject(out);
    if (!ctrlLocked) ctrlArmed = false;
    if (!altLocked) altArmed = false;
  }

  // Sequence helpers — these are emitted with no modifier processing.
  const ESC = '\x1b';
  const ARROW_UP    = `${ESC}[A`;
  const ARROW_DOWN  = `${ESC}[B`;
  const ARROW_RIGHT = `${ESC}[C`;
  const ARROW_LEFT  = `${ESC}[D`;

  function pressEsc(): void  { fireKey(ESC, { allowMods: false }); }
  function pressTab(): void  { fireKey('\t', { allowMods: false }); }
  function pressUp(): void   { fireKey(ARROW_UP, { allowMods: false }); }
  function pressDown(): void { fireKey(ARROW_DOWN, { allowMods: false }); }
  function pressLeft(): void { fireKey(ARROW_LEFT, { allowMods: false }); }
  function pressRight(): void{ fireKey(ARROW_RIGHT, { allowMods: false }); }
  function pressPipe(): void { fireKey('|'); }
  function pressTilde(): void{ fireKey('~'); }
  function pressSlash(): void{ fireKey('/'); }
</script>

<div class="keybar" class:visible={keyboardVisible} aria-label="Terminal modifier bar">
  <button type="button" class="key" onclick={pressEsc}>Esc</button>
  <button type="button" class="key" onclick={pressTab}>Tab</button>
  <button
    type="button"
    class="key mod"
    class:armed={ctrlArmed && !ctrlLocked}
    class:locked={ctrlLocked}
    onclick={toggleCtrl}
    oncontextmenu={(e) => { e.preventDefault(); lockCtrl(); }}
  >Ctrl</button>
  <button
    type="button"
    class="key mod"
    class:armed={altArmed && !altLocked}
    class:locked={altLocked}
    onclick={toggleAlt}
    oncontextmenu={(e) => { e.preventDefault(); lockAlt(); }}
  >Alt</button>
  <button type="button" class="key" onclick={pressUp}>↑</button>
  <button type="button" class="key" onclick={pressDown}>↓</button>
  <button type="button" class="key" onclick={pressLeft}>←</button>
  <button type="button" class="key" onclick={pressRight}>→</button>
  <button type="button" class="key" onclick={pressPipe}>|</button>
  <button type="button" class="key" onclick={pressTilde}>~</button>
  <button type="button" class="key" onclick={pressSlash}>/</button>
</div>

<style>
  .keybar {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 4px 6px;
    background: #111114;
    border-top: 1px solid #25252c;
    overflow-x: auto;
    -webkit-overflow-scrolling: touch;
    flex-shrink: 0;
    /* Hidden by default; the parent toggles `.visible` based on keyboard state. */
    display: none;
  }

  .keybar.visible {
    display: flex;
  }

  .key {
    flex: 0 0 auto;
    min-width: 36px;
    height: 32px;
    padding: 0 8px;
    border: 1px solid #2a2a32;
    border-radius: 6px;
    background: #1a1a22;
    color: #e0e0e8;
    font-family: var(--font-mono, ui-monospace, Menlo, monospace);
    font-size: 0.78rem;
    font-weight: 600;
    cursor: pointer;
    -webkit-tap-highlight-color: transparent;
    user-select: none;
    touch-action: manipulation;
  }

  .key:active {
    background: #25252e;
  }

  .key.mod.armed {
    background: rgba(99, 179, 237, 0.18);
    border-color: rgba(99, 179, 237, 0.6);
    color: #9fcdf6;
  }

  .key.mod.locked {
    background: rgba(99, 179, 237, 0.32);
    border-color: rgba(99, 179, 237, 0.9);
    color: #cfe5fb;
    box-shadow: inset 0 0 0 1px rgba(99, 179, 237, 0.5);
  }
</style>
