/**
 * Shared sticky-modifier state for the CLI soft keyboard.
 *
 * The Termius-style keybar lets the user tap Ctrl/Alt to arm a modifier
 * that applies to the NEXT key press. Wave 1 kept the state inside
 * MobileKeybar.svelte and applied the transform inside its dispatch()
 * function. That worked for keys tapped ON the keybar but silently
 * failed for anything the user typed on the iOS native keyboard — those
 * bytes flow straight into xterm.js via term.onData() and never touch
 * the keybar's dispatch path, so "tap Ctrl, type c" sent a literal 'c'
 * to the PTY instead of ^C.
 *
 * Phase 13 Wave 2.5 lifts the state and the transform into this shared
 * store. XtermPane intercepts onData, runs the bytes through transform(),
 * and calls clearArmed() so one-shot mods reset after every dispatch.
 * MobileKeybar now just renders reactive state from this store and calls
 * toggleSticky() for Ctrl/Alt taps.
 */

const DOUBLE_TAP_MS = 400;

class KeybarModifiers {
  /** One-shot: cleared after the next non-modifier dispatch. */
  ctrlArmed = $state(false);
  altArmed = $state(false);
  /** Persistent: stays on until the user taps the mod again. */
  ctrlLocked = $state(false);
  altLocked = $state(false);

  /**
   * Double-tap detector for promoting an armed mod to a lock. We record
   * the id + timestamp of the most recent sticky tap; if the SAME sticky
   * is tapped again within DOUBLE_TAP_MS, the arm becomes a lock.
   */
  private lastStickyTap: { id: 'ctrl' | 'alt'; t: number } | null = null;

  /** True when any modifier is currently armed or locked. */
  get hasActive(): boolean {
    return this.ctrlArmed || this.altArmed || this.ctrlLocked || this.altLocked;
  }

  /**
   * Handle a tap on a sticky modifier key from the keybar.
   *
   * State machine:
   *   off → tap  → armed
   *   armed → tap within 400ms → locked
   *   armed → tap elsewhere → off (via clearArmed after dispatch)
   *   locked → tap → off
   */
  toggleSticky(id: 'ctrl' | 'alt'): void {
    const now = typeof performance !== 'undefined' ? performance.now() : Date.now();
    const isDoubleTap =
      this.lastStickyTap !== null &&
      this.lastStickyTap.id === id &&
      now - this.lastStickyTap.t < DOUBLE_TAP_MS;
    this.lastStickyTap = { id, t: now };

    const armed = id === 'ctrl' ? this.ctrlArmed : this.altArmed;
    const locked = id === 'ctrl' ? this.ctrlLocked : this.altLocked;

    // If currently locked, any tap on the same mod releases it.
    if (locked) {
      if (id === 'ctrl') {
        this.ctrlLocked = false;
        this.ctrlArmed = false;
      } else {
        this.altLocked = false;
        this.altArmed = false;
      }
      return;
    }

    // Double-tap from armed → promote to locked.
    if (isDoubleTap && armed) {
      if (id === 'ctrl') this.ctrlLocked = true;
      else this.altLocked = true;
      return;
    }

    // Single tap toggles just this mod's armed state.
    if (id === 'ctrl') this.ctrlArmed = !this.ctrlArmed;
    else this.altArmed = !this.altArmed;
  }

  /**
   * Apply currently-active modifiers to raw input bytes. Returns the
   * transformed string. Callers MUST also call clearArmed() afterwards
   * so one-shot armed mods reset for the next key.
   *
   * For an empty input this is a no-op (no mods applied, no clear).
   */
  transform(bytes: string): string {
    if (bytes.length === 0) return bytes;
    let out = bytes;
    const ctrlActive = this.ctrlLocked || this.ctrlArmed;
    const altActive = this.altLocked || this.altArmed;

    if (ctrlActive) {
      // Ctrl + printable ASCII → control byte (bit 5 cleared). xterm/VT
      // convention: Ctrl-@ = NUL, Ctrl-A = 0x01, … Ctrl-_ = 0x1f. Works
      // for uppercase, lowercase, and the @[\]^_` range between them.
      // We only transform the first byte so multi-byte sequences (e.g.
      // CSI escape codes from the arrow keys) stay sane.
      //
      // Caught by Copilot PR #93 review: a previous version blanket-XOR'd
      // the 0x20..0x3f range with 0x40, which produced nonsense for all
      // but 0x3f — e.g. Ctrl-Space would have become '`' (0x60) instead
      // of the conventional NUL. Only two Ctrl combinations have a
      // defined meaning below 0x40, so special-case them and pass
      // everything else through unmodified (see fall-through comment
      // below).
      const first = out.charCodeAt(0);
      if (first >= 0x40 && first <= 0x7e) {
        out = String.fromCharCode(first & 0x1f) + out.slice(1);
      } else if (first === 0x20) {
        // Ctrl-Space → NUL (0x00). Used by readline to set a mark.
        out = String.fromCharCode(0x00) + out.slice(1);
      } else if (first === 0x3f) {
        // Ctrl-? → DEL (0x7f). Rare but legal.
        out = String.fromCharCode(0x7f) + out.slice(1);
      }
      // Anything else (digits, common punctuation) has no defined Ctrl
      // transform — pass it through unmodified so users can still type,
      // say, Ctrl-1 and have it land as a literal '1' rather than a
      // garbled control byte.
    }
    if (altActive) {
      // xterm's portable Meta encoding is ESC + key byte.
      out = '\x1b' + out;
    }
    return out;
  }

  /**
   * One-shot armed mods auto-release after dispatch. Locked mods stay
   * active until the user explicitly taps them off.
   */
  clearArmed(): void {
    if (!this.ctrlLocked) this.ctrlArmed = false;
    if (!this.altLocked) this.altArmed = false;
  }

  /** Hard reset — e.g. on logout or explicit user action. */
  reset(): void {
    this.ctrlArmed = false;
    this.altArmed = false;
    this.ctrlLocked = false;
    this.altLocked = false;
    this.lastStickyTap = null;
  }
}

export const keybarModifiers = new KeybarModifiers();
