import Foundation

/// Definition of a single key on the native keybar or specialty grid.
///
/// Mirrors the web PWA's `KeySpec` interface from `web/src/lib/shell/keys.ts`.
/// Each key has an identifier, display label, an optional SF Symbol icon, and
/// either a raw byte sequence to inject or a modifier flag.
///
/// Byte sequences follow xterm/VT conventions:
///   - Ctrl-letter  -> ASCII 0x01..0x1A
///   - Esc          -> 0x1b
///   - Tab          -> 0x09
///   - Arrows       -> CSI \u{1b}[A..D
///   - F1..F4       -> SS3 \u{1b}OP..S
///   - F5..F12      -> CSI \u{1b}[15~..\u{1b}[24~
struct KeySpec: Identifiable, Equatable, Sendable {
    /// Stable identifier -- used in customize config and lookups. Never change once shipped.
    let id: String

    /// Visible label on the button (may use unicode glyphs).
    let label: String

    /// Optional SF Symbol name for icon-based rendering.
    let icon: String?

    /// Raw bytes injected into the PTY when pressed (empty for sticky modifiers).
    let bytes: String

    /// True for modifier latches (Ctrl/Alt) -- these emit no bytes themselves.
    let isModifier: Bool

    /// Grouping for the specialty grid organize/customize picker.
    let group: KeyGroup

    /// Human-friendly description shown in the customize picker.
    let description: String?

    init(
        id: String,
        label: String,
        icon: String? = nil,
        bytes: String = "",
        isModifier: Bool = false,
        group: KeyGroup = .edit,
        description: String? = nil
    ) {
        self.id = id
        self.label = label
        self.icon = icon
        self.bytes = bytes
        self.isModifier = isModifier
        self.group = group
        self.description = description
    }
}

// MARK: - Key Group

enum KeyGroup: String, CaseIterable, Sendable {
    case modifier
    case edit
    case nav
    case symbol
    case ctrl
    case tmux
    case function
}

// MARK: - Terminal Escape Sequences

private enum Seq {
    static let esc = "\u{1b}"
    static let csi = "\u{1b}["
    static let ss3 = "\u{1b}O"
    static let tmuxPrefix = "\u{02}" // Ctrl-B
}

/// Build a Ctrl-letter byte (Ctrl+A = 0x01, Ctrl+Z = 0x1A).
/// Returns the original letter unchanged if it's not A-Z.
private func ctrlByte(_ letter: Character) -> String {
    guard let scalar = letter.uppercased().unicodeScalars.first else {
        return String(letter)
    }
    let code = scalar.value
    guard code >= 65, code <= 90 else { return String(letter) } // A-Z only
    guard let controlScalar = UnicodeScalar(code - 64) else {
        return String(letter)
    }
    return String(controlScalar)
}

// MARK: - Key Library

/// The full library of keys available for the keybar and specialty grid.
/// Mirrors the web PWA's KEY_LIBRARY.
enum KeyLibrary {

    static let all: [KeySpec] = modifiers + editNav + arrows + symbols + ctrlCombos + tmuxKeys + functionKeys

    // -- Modifiers (sticky latches) ----------------------------------------

    static let modifiers: [KeySpec] = [
        KeySpec(id: "ctrl", label: "Ctrl", icon: "control", isModifier: true, group: .modifier, description: "Hold Ctrl for next key"),
        KeySpec(id: "alt", label: "Alt", icon: "option", isModifier: true, group: .modifier, description: "Hold Alt (Meta) for next key"),
    ]

    // -- Edit / Nav --------------------------------------------------------

    static let editNav: [KeySpec] = [
        KeySpec(id: "esc", label: "Esc", icon: "escape", bytes: Seq.esc, group: .edit, description: "Escape"),
        KeySpec(id: "tab", label: "Tab", icon: "arrow.right.to.line", bytes: "\t", group: .edit, description: "Tab"),
        KeySpec(id: "enter", label: "\u{23CE}", bytes: "\r", group: .edit, description: "Enter / return"),
        KeySpec(id: "backspace", label: "\u{232B}", bytes: "\u{7f}", group: .edit, description: "Backspace"),
        KeySpec(id: "home", label: "Home", bytes: "\(Seq.csi)H", group: .nav, description: "Home"),
        KeySpec(id: "end", label: "End", bytes: "\(Seq.csi)F", group: .nav, description: "End"),
        KeySpec(id: "pgup", label: "PgUp", bytes: "\(Seq.csi)5~", group: .nav, description: "Page Up"),
        KeySpec(id: "pgdn", label: "PgDn", bytes: "\(Seq.csi)6~", group: .nav, description: "Page Down"),
        KeySpec(id: "ins", label: "Ins", bytes: "\(Seq.csi)2~", group: .nav, description: "Insert"),
        KeySpec(id: "del", label: "Del", bytes: "\(Seq.csi)3~", group: .nav, description: "Delete forward"),
    ]

    // -- Arrows ------------------------------------------------------------

    static let arrows: [KeySpec] = [
        KeySpec(id: "arrow-up", label: "\u{2191}", icon: "arrowtriangle.up.fill", bytes: "\(Seq.csi)A", group: .nav, description: "Cursor up"),
        KeySpec(id: "arrow-down", label: "\u{2193}", icon: "arrowtriangle.down.fill", bytes: "\(Seq.csi)B", group: .nav, description: "Cursor down"),
        KeySpec(id: "arrow-left", label: "\u{2190}", icon: "arrowtriangle.left.fill", bytes: "\(Seq.csi)D", group: .nav, description: "Cursor left"),
        KeySpec(id: "arrow-right", label: "\u{2192}", icon: "arrowtriangle.right.fill", bytes: "\(Seq.csi)C", group: .nav, description: "Cursor right"),
    ]

    // -- Symbols -----------------------------------------------------------

    static let symbols: [KeySpec] = [
        KeySpec(id: "pipe", label: "|", bytes: "|", group: .symbol),
        KeySpec(id: "slash", label: "/", bytes: "/", group: .symbol),
        KeySpec(id: "backslash", label: "\\", bytes: "\\", group: .symbol),
        KeySpec(id: "dash", label: "-", bytes: "-", group: .symbol),
        KeySpec(id: "underscore", label: "_", bytes: "_", group: .symbol),
        KeySpec(id: "tilde", label: "~", bytes: "~", group: .symbol),
        KeySpec(id: "backtick", label: "`", bytes: "`", group: .symbol),
        KeySpec(id: "caret", label: "^", bytes: "^", group: .symbol),
        KeySpec(id: "amp", label: "&", bytes: "&", group: .symbol),
        KeySpec(id: "star", label: "*", bytes: "*", group: .symbol),
        KeySpec(id: "lbrace", label: "{", bytes: "{", group: .symbol),
        KeySpec(id: "rbrace", label: "}", bytes: "}", group: .symbol),
        KeySpec(id: "lbracket", label: "[", bytes: "[", group: .symbol),
        KeySpec(id: "rbracket", label: "]", bytes: "]", group: .symbol),
        KeySpec(id: "lparen", label: "(", bytes: "(", group: .symbol),
        KeySpec(id: "rparen", label: ")", bytes: ")", group: .symbol),
        KeySpec(id: "lt", label: "<", bytes: "<", group: .symbol),
        KeySpec(id: "gt", label: ">", bytes: ">", group: .symbol),
        KeySpec(id: "eq", label: "=", bytes: "=", group: .symbol),
        KeySpec(id: "plus", label: "+", bytes: "+", group: .symbol),
        KeySpec(id: "colon", label: ":", bytes: ":", group: .symbol),
        KeySpec(id: "semicolon", label: ";", bytes: ";", group: .symbol),
        KeySpec(id: "quote", label: "'", bytes: "'", group: .symbol),
        KeySpec(id: "dquote", label: "\"", bytes: "\"", group: .symbol),
    ]

    // -- Common Ctrl combos ------------------------------------------------

    static let ctrlCombos: [KeySpec] = [
        KeySpec(id: "ctrl-a", label: "^A", bytes: ctrlByte("a"), group: .ctrl, description: "Beginning of line"),
        KeySpec(id: "ctrl-c", label: "^C", bytes: ctrlByte("c"), group: .ctrl, description: "SIGINT -- kill foreground"),
        KeySpec(id: "ctrl-d", label: "^D", bytes: ctrlByte("d"), group: .ctrl, description: "EOF / logout"),
        KeySpec(id: "ctrl-e", label: "^E", bytes: ctrlByte("e"), group: .ctrl, description: "End of line"),
        KeySpec(id: "ctrl-k", label: "^K", bytes: ctrlByte("k"), group: .ctrl, description: "Kill to end of line"),
        KeySpec(id: "ctrl-l", label: "^L", bytes: ctrlByte("l"), group: .ctrl, description: "Clear screen"),
        KeySpec(id: "ctrl-r", label: "^R", bytes: ctrlByte("r"), group: .ctrl, description: "History search"),
        KeySpec(id: "ctrl-u", label: "^U", bytes: ctrlByte("u"), group: .ctrl, description: "Kill line backwards"),
        KeySpec(id: "ctrl-w", label: "^W", bytes: ctrlByte("w"), group: .ctrl, description: "Kill word backwards"),
        KeySpec(id: "ctrl-z", label: "^Z", bytes: ctrlByte("z"), group: .ctrl, description: "SIGTSTP -- suspend"),
    ]

    // -- Tmux quick-tap ----------------------------------------------------

    static let tmuxKeys: [KeySpec] = [
        KeySpec(id: "tmux-prefix", label: "^B", bytes: Seq.tmuxPrefix, group: .tmux, description: "Tmux prefix (Ctrl-B)"),
        KeySpec(id: "tmux-scroll", label: "\u{2912}", bytes: "\(Seq.tmuxPrefix)[", group: .tmux, description: "Tmux copy-mode (scroll)"),
        KeySpec(id: "tmux-zoom", label: "^Bz", bytes: "\(Seq.tmuxPrefix)z", group: .tmux, description: "Tmux zoom pane"),
        KeySpec(id: "tmux-next", label: "^Bn", bytes: "\(Seq.tmuxPrefix)n", group: .tmux, description: "Tmux next window"),
        KeySpec(id: "tmux-prev", label: "^Bp", bytes: "\(Seq.tmuxPrefix)p", group: .tmux, description: "Tmux prev window"),
        KeySpec(id: "tmux-detach", label: "^Bd", bytes: "\(Seq.tmuxPrefix)d", group: .tmux, description: "Tmux detach"),
    ]

    // -- Function keys -----------------------------------------------------

    static let functionKeys: [KeySpec] = [
        KeySpec(id: "f1", label: "F1", bytes: "\(Seq.ss3)P", group: .function),
        KeySpec(id: "f2", label: "F2", bytes: "\(Seq.ss3)Q", group: .function),
        KeySpec(id: "f3", label: "F3", bytes: "\(Seq.ss3)R", group: .function),
        KeySpec(id: "f4", label: "F4", bytes: "\(Seq.ss3)S", group: .function),
        KeySpec(id: "f5", label: "F5", bytes: "\(Seq.csi)15~", group: .function),
        KeySpec(id: "f6", label: "F6", bytes: "\(Seq.csi)17~", group: .function),
        KeySpec(id: "f7", label: "F7", bytes: "\(Seq.csi)18~", group: .function),
        KeySpec(id: "f8", label: "F8", bytes: "\(Seq.csi)19~", group: .function),
        KeySpec(id: "f9", label: "F9", bytes: "\(Seq.csi)20~", group: .function),
        KeySpec(id: "f10", label: "F10", bytes: "\(Seq.csi)21~", group: .function),
        KeySpec(id: "f11", label: "F11", bytes: "\(Seq.csi)23~", group: .function),
        KeySpec(id: "f12", label: "F12", bytes: "\(Seq.csi)24~", group: .function),
    ]

    /// O(1) lookup by key ID.
    private static let index: [String: KeySpec] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    }()

    static func get(_ id: String) -> KeySpec? {
        index[id]
    }
}

// MARK: - Default Layouts

extension KeyLibrary {

    /// Default accessory bar key IDs -- sits above the iOS keyboard.
    /// Mirrors the web's DEFAULT_ACCESSORY_KEYS.
    static let defaultBarIDs: [String] = [
        "tmux-scroll",
        "pgup", "pgdn",
        "esc", "tab",
        "ctrl", "alt",
        "arrow-up", "arrow-down", "arrow-left", "arrow-right",
        "lbracket",
        "pipe", "slash", "dash", "tilde",
    ]

    /// Default specialty grid key IDs -- replaces the iOS keyboard.
    /// Mirrors the web's DEFAULT_SPECIALTY_KEYS.
    static let defaultGridIDs: [String] = [
        // edit / nav
        "esc", "tab", "home", "end", "pgup", "pgdn", "ins", "del",
        // arrows
        "arrow-up", "arrow-down", "arrow-left", "arrow-right",
        // modifiers + common symbols
        "ctrl", "alt",
        "pipe", "backslash", "slash", "dash", "underscore", "tilde", "backtick",
        "quote", "dquote", "lbrace", "rbrace",
        // ctrl combos
        "ctrl-a", "ctrl-c", "ctrl-d", "ctrl-l", "ctrl-r", "ctrl-u", "ctrl-w", "ctrl-z",
        // tmux
        "tmux-prefix", "tmux-scroll", "tmux-zoom", "tmux-next", "tmux-prev", "tmux-detach",
        // function row
        "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
    ]

    /// Resolve a list of key IDs into KeySpec instances, filtering out any
    /// unrecognized IDs (future-proofing against removed keys).
    static func resolve(_ ids: [String]) -> [KeySpec] {
        ids.compactMap { get($0) }
    }

    /// The default accessory bar keys, resolved.
    static var defaultBar: [KeySpec] {
        resolve(defaultBarIDs)
    }

    /// The default specialty grid keys, resolved.
    static var defaultGrid: [KeySpec] {
        resolve(defaultGridIDs)
    }
}
