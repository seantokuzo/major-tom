/**
 * Keymap library for the Termius-style soft keyboard.
 *
 * Every specialty key the keybar can render lives in `KEY_LIBRARY`. The
 * accessory row and specialty grid each pick from this library by id.
 * Defaults are set in `DEFAULT_ACCESSORY_KEYS` / `DEFAULT_SPECIALTY_KEYS`.
 *
 * Byte sequences follow xterm/VT conventions:
 *   - Ctrl-letter → ASCII 0x01..0x1A
 *   - Esc         → 0x1b
 *   - Tab         → 0x09
 *   - Arrows      → CSI \x1b[A..D
 *   - F1..F4      → SS3 \x1bOP..S
 *   - F5..F12     → CSI \x1b[15~..\x1b[24~
 *   - Tmux prefix → 0x02 (Ctrl-B)
 */

export interface KeySpec {
  /** Stable identifier — used in customize config + lookups. Never change once shipped. */
  id: string;
  /** Visible label on the button (may use unicode glyphs). */
  label: string;
  /** Raw bytes injected into the PTY when pressed (empty for sticky modifiers). */
  bytes: string;
  /** True for modifier latches (Ctrl/Alt) — these emit no bytes themselves. */
  sticky?: boolean;
  /** Human-friendly description shown in the customize picker. */
  description?: string;
  /** Optional grouping label for the customize picker. */
  group?: 'modifier' | 'edit' | 'nav' | 'symbol' | 'ctrl' | 'tmux' | 'function';
}

const ESC = '\x1b';
const CSI = '\x1b[';
const SS3 = '\x1bO';
const TMUX = '\x02'; // Ctrl-B prefix

/** Build a Ctrl-letter byte. */
function ctrlByte(letter: string): string {
  const code = letter.toLowerCase().charCodeAt(0);
  if (code < 97 || code > 122) return letter;
  return String.fromCharCode(code - 96);
}

export const KEY_LIBRARY: KeySpec[] = [
  // ── Modifiers (sticky latches) ──────────────────────────────────────
  { id: 'ctrl', label: 'Ctrl', bytes: '', sticky: true, group: 'modifier', description: 'Hold Ctrl for next key' },
  { id: 'alt', label: 'Alt', bytes: '', sticky: true, group: 'modifier', description: 'Hold Alt (Meta) for next key' },

  // ── Edit / nav ──────────────────────────────────────────────────────
  { id: 'esc', label: 'Esc', bytes: ESC, group: 'edit', description: 'Escape' },
  { id: 'tab', label: 'Tab', bytes: '\t', group: 'edit', description: 'Tab' },
  { id: 'enter', label: '⏎', bytes: '\r', group: 'edit', description: 'Enter / return' },
  { id: 'backspace', label: '⌫', bytes: '\x7f', group: 'edit', description: 'Backspace' },
  { id: 'home', label: 'Home', bytes: `${CSI}H`, group: 'nav', description: 'Home' },
  { id: 'end', label: 'End', bytes: `${CSI}F`, group: 'nav', description: 'End' },
  { id: 'pgup', label: 'PgUp', bytes: `${CSI}5~`, group: 'nav', description: 'Page Up' },
  { id: 'pgdn', label: 'PgDn', bytes: `${CSI}6~`, group: 'nav', description: 'Page Down' },
  { id: 'ins', label: 'Ins', bytes: `${CSI}2~`, group: 'nav', description: 'Insert' },
  { id: 'del', label: 'Del', bytes: `${CSI}3~`, group: 'nav', description: 'Delete forward' },

  // ── Arrows ──────────────────────────────────────────────────────────
  { id: 'arrow-up', label: '↑', bytes: `${CSI}A`, group: 'nav', description: 'Cursor up' },
  { id: 'arrow-down', label: '↓', bytes: `${CSI}B`, group: 'nav', description: 'Cursor down' },
  { id: 'arrow-left', label: '←', bytes: `${CSI}D`, group: 'nav', description: 'Cursor left' },
  { id: 'arrow-right', label: '→', bytes: `${CSI}C`, group: 'nav', description: 'Cursor right' },

  // ── Symbols ─────────────────────────────────────────────────────────
  { id: 'pipe', label: '|', bytes: '|', group: 'symbol' },
  { id: 'slash', label: '/', bytes: '/', group: 'symbol' },
  { id: 'backslash', label: '\\', bytes: '\\', group: 'symbol' },
  { id: 'dash', label: '-', bytes: '-', group: 'symbol' },
  { id: 'underscore', label: '_', bytes: '_', group: 'symbol' },
  { id: 'tilde', label: '~', bytes: '~', group: 'symbol' },
  { id: 'backtick', label: '`', bytes: '`', group: 'symbol' },
  { id: 'caret', label: '^', bytes: '^', group: 'symbol' },
  { id: 'amp', label: '&', bytes: '&', group: 'symbol' },
  { id: 'star', label: '*', bytes: '*', group: 'symbol' },
  { id: 'lbrace', label: '{', bytes: '{', group: 'symbol' },
  { id: 'rbrace', label: '}', bytes: '}', group: 'symbol' },
  { id: 'lbracket', label: '[', bytes: '[', group: 'symbol' },
  { id: 'rbracket', label: ']', bytes: ']', group: 'symbol' },
  { id: 'lparen', label: '(', bytes: '(', group: 'symbol' },
  { id: 'rparen', label: ')', bytes: ')', group: 'symbol' },
  { id: 'lt', label: '<', bytes: '<', group: 'symbol' },
  { id: 'gt', label: '>', bytes: '>', group: 'symbol' },
  { id: 'eq', label: '=', bytes: '=', group: 'symbol' },
  { id: 'plus', label: '+', bytes: '+', group: 'symbol' },
  { id: 'colon', label: ':', bytes: ':', group: 'symbol' },
  { id: 'semicolon', label: ';', bytes: ';', group: 'symbol' },
  { id: 'quote', label: "'", bytes: "'", group: 'symbol' },
  { id: 'dquote', label: '"', bytes: '"', group: 'symbol' },

  // ── Common Ctrl combos ──────────────────────────────────────────────
  { id: 'ctrl-a', label: '^A', bytes: ctrlByte('a'), group: 'ctrl', description: 'Beginning of line' },
  { id: 'ctrl-c', label: '^C', bytes: ctrlByte('c'), group: 'ctrl', description: 'SIGINT — kill foreground' },
  { id: 'ctrl-d', label: '^D', bytes: ctrlByte('d'), group: 'ctrl', description: 'EOF / logout' },
  { id: 'ctrl-e', label: '^E', bytes: ctrlByte('e'), group: 'ctrl', description: 'End of line' },
  { id: 'ctrl-k', label: '^K', bytes: ctrlByte('k'), group: 'ctrl', description: 'Kill to end of line' },
  { id: 'ctrl-l', label: '^L', bytes: ctrlByte('l'), group: 'ctrl', description: 'Clear screen' },
  { id: 'ctrl-r', label: '^R', bytes: ctrlByte('r'), group: 'ctrl', description: 'History search' },
  { id: 'ctrl-u', label: '^U', bytes: ctrlByte('u'), group: 'ctrl', description: 'Kill line backwards' },
  { id: 'ctrl-w', label: '^W', bytes: ctrlByte('w'), group: 'ctrl', description: 'Kill word backwards' },
  { id: 'ctrl-z', label: '^Z', bytes: ctrlByte('z'), group: 'ctrl', description: 'SIGTSTP — suspend' },

  // ── Tmux quick-tap ──────────────────────────────────────────────────
  { id: 'tmux-prefix', label: '^B', bytes: TMUX, group: 'tmux', description: 'Tmux prefix (Ctrl-B)' },
  {
    id: 'tmux-scroll',
    label: '⤒',
    bytes: `${TMUX}[`,
    group: 'tmux',
    description: 'Tmux copy-mode (scroll)',
  },
  { id: 'tmux-zoom', label: '^Bz', bytes: `${TMUX}z`, group: 'tmux', description: 'Tmux zoom pane' },
  { id: 'tmux-next', label: '^Bn', bytes: `${TMUX}n`, group: 'tmux', description: 'Tmux next window' },
  { id: 'tmux-prev', label: '^Bp', bytes: `${TMUX}p`, group: 'tmux', description: 'Tmux prev window' },
  { id: 'tmux-detach', label: '^Bd', bytes: `${TMUX}d`, group: 'tmux', description: 'Tmux detach' },

  // ── Function keys (Termius defaults the F-row to bottom of grid) ────
  { id: 'f1', label: 'F1', bytes: `${SS3}P`, group: 'function' },
  { id: 'f2', label: 'F2', bytes: `${SS3}Q`, group: 'function' },
  { id: 'f3', label: 'F3', bytes: `${SS3}R`, group: 'function' },
  { id: 'f4', label: 'F4', bytes: `${SS3}S`, group: 'function' },
  { id: 'f5', label: 'F5', bytes: `${CSI}15~`, group: 'function' },
  { id: 'f6', label: 'F6', bytes: `${CSI}17~`, group: 'function' },
  { id: 'f7', label: 'F7', bytes: `${CSI}18~`, group: 'function' },
  { id: 'f8', label: 'F8', bytes: `${CSI}19~`, group: 'function' },
  { id: 'f9', label: 'F9', bytes: `${CSI}20~`, group: 'function' },
  { id: 'f10', label: 'F10', bytes: `${CSI}21~`, group: 'function' },
  { id: 'f11', label: 'F11', bytes: `${CSI}23~`, group: 'function' },
  { id: 'f12', label: 'F12', bytes: `${CSI}24~`, group: 'function' },
];

/** Index for O(1) lookups. */
const KEY_INDEX = new Map<string, KeySpec>(KEY_LIBRARY.map((k) => [k.id, k]));

export function getKey(id: string): KeySpec | undefined {
  return KEY_INDEX.get(id);
}

/**
 * Default accessory row — sits above the iOS native keyboard.
 *
 * `tmux-scroll` is FIRST because it's the single most-used key on the bar
 * (single-tap entry to tmux copy-mode for scrolling). Customize button is
 * the rendered last by the component, not in this list.
 *
 * Phase 13 Wave 2.5 additions:
 *   - `pgup`/`pgdn` — in-terminal scrolling without entering copy-mode
 *     (most applications handle these natively; also works as "scroll
 *     through bash history" equivalents after Up/Down exhaustion).
 *   - `lbracket` — the raw `[` key is impossible to reach on iOS numeric
 *     row without a shift-chord. Also doubles as the escape hatch into
 *     tmux copy-mode when combined with the Ctrl latch (`Ctrl-B [`).
 */
export const DEFAULT_ACCESSORY_KEYS: string[] = [
  'tmux-scroll',
  'pgup',
  'pgdn',
  'esc',
  'tab',
  'ctrl',
  'alt',
  'arrow-up',
  'arrow-down',
  'arrow-left',
  'arrow-right',
  'lbracket',
  'pipe',
  'slash',
  'dash',
  'tilde',
];

/**
 * Default specialty grid — replaces the iOS native keyboard.
 *
 * Layout intent (the component flows these into a wrap-grid):
 *   1. Edit/nav block
 *   2. Symbol block
 *   3. Ctrl combos block
 *   4. Tmux block
 *   5. F-keys row pinned to the bottom (Termius default)
 */
export const DEFAULT_SPECIALTY_KEYS: string[] = [
  // edit / nav
  'esc',
  'tab',
  'home',
  'end',
  'pgup',
  'pgdn',
  'ins',
  'del',
  // arrows
  'arrow-up',
  'arrow-down',
  'arrow-left',
  'arrow-right',
  // modifiers + common symbols
  'ctrl',
  'alt',
  'pipe',
  'backslash',
  'slash',
  'dash',
  'underscore',
  'tilde',
  'backtick',
  'quote',
  'dquote',
  'lbrace',
  'rbrace',
  // ctrl combos
  'ctrl-a',
  'ctrl-c',
  'ctrl-d',
  'ctrl-l',
  'ctrl-r',
  'ctrl-u',
  'ctrl-w',
  'ctrl-z',
  // tmux
  'tmux-prefix',
  'tmux-scroll',
  'tmux-zoom',
  'tmux-next',
  'tmux-prev',
  'tmux-detach',
  // function row (rendered last so it lands at the bottom of the grid)
  'f1',
  'f2',
  'f3',
  'f4',
  'f5',
  'f6',
  'f7',
  'f8',
  'f9',
  'f10',
  'f11',
  'f12',
];
