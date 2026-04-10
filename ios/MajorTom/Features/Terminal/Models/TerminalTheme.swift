import Foundation

/// Terminal color theme definition for xterm.js.
///
/// Each theme provides the full set of 19 xterm colors used by the JS bridge.
/// Themes are injected into the WKWebView via `MajorTom.setTheme(theme)` and
/// persisted by the `KeybarViewModel` preference sync system.
struct TerminalTheme: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String

    // Core colors
    let background: String
    let foreground: String
    let cursor: String
    let cursorAccent: String
    let selectionBackground: String

    // Standard ANSI colors
    let black: String
    let red: String
    let green: String
    let yellow: String
    let blue: String
    let magenta: String
    let cyan: String
    let white: String

    // Bright ANSI colors
    let brightBlack: String
    let brightRed: String
    let brightGreen: String
    let brightYellow: String
    let brightBlue: String
    let brightMagenta: String
    let brightCyan: String
    let brightWhite: String

    /// Dictionary representation for passing to the JS bridge's `MajorTom.setTheme()`.
    var asDictionary: [String: String] {
        [
            "background": background,
            "foreground": foreground,
            "cursor": cursor,
            "cursorAccent": cursorAccent,
            "selectionBackground": selectionBackground,
            "black": black,
            "red": red,
            "green": green,
            "yellow": yellow,
            "blue": blue,
            "magenta": magenta,
            "cyan": cyan,
            "white": white,
            "brightBlack": brightBlack,
            "brightRed": brightRed,
            "brightGreen": brightGreen,
            "brightYellow": brightYellow,
            "brightBlue": brightBlue,
            "brightMagenta": brightMagenta,
            "brightCyan": brightCyan,
            "brightWhite": brightWhite,
        ]
    }
}

// MARK: - Preset Themes

extension TerminalTheme {

    /// All available themes for the picker UI.
    static let all: [TerminalTheme] = [
        .majorTom, .dracula, .solarizedDark, .solarizedLight, .monokai, .nord,
    ]

    /// Default Major Tom dark theme — matches the app's design system.
    static let majorTom = TerminalTheme(
        id: "major-tom",
        name: "Major Tom",
        background: "#0d0d12",
        foreground: "#e8e8e8",
        cursor: "#f2a641",
        cursorAccent: "#0d0d12",
        selectionBackground: "#f2a64140",
        black: "#1a1a24",
        red: "#f24d4d",
        green: "#4dd97a",
        yellow: "#f2cc33",
        blue: "#4d8af2",
        magenta: "#b84df2",
        cyan: "#4dd9d9",
        white: "#e8e8e8",
        brightBlack: "#666680",
        brightRed: "#f27a7a",
        brightGreen: "#7ae89e",
        brightYellow: "#f2d966",
        brightBlue: "#7ab3f2",
        brightMagenta: "#cc7af2",
        brightCyan: "#7ae8e8",
        brightWhite: "#ffffff"
    )

    /// Dracula — popular dark theme with purple accents.
    static let dracula = TerminalTheme(
        id: "dracula",
        name: "Dracula",
        background: "#282a36",
        foreground: "#f8f8f2",
        cursor: "#f8f8f2",
        cursorAccent: "#282a36",
        selectionBackground: "#44475a80",
        black: "#21222c",
        red: "#ff5555",
        green: "#50fa7b",
        yellow: "#f1fa8c",
        blue: "#bd93f9",
        magenta: "#ff79c6",
        cyan: "#8be9fd",
        white: "#f8f8f2",
        brightBlack: "#6272a4",
        brightRed: "#ff6e6e",
        brightGreen: "#69ff94",
        brightYellow: "#ffffa5",
        brightBlue: "#d6acff",
        brightMagenta: "#ff92df",
        brightCyan: "#a4ffff",
        brightWhite: "#ffffff"
    )

    /// Solarized Dark — Ethan Schoonover's warm dark palette.
    static let solarizedDark = TerminalTheme(
        id: "solarized-dark",
        name: "Solarized Dark",
        background: "#002b36",
        foreground: "#839496",
        cursor: "#93a1a1",
        cursorAccent: "#002b36",
        selectionBackground: "#073642",
        black: "#073642",
        red: "#dc322f",
        green: "#859900",
        yellow: "#b58900",
        blue: "#268bd2",
        magenta: "#d33682",
        cyan: "#2aa198",
        white: "#eee8d5",
        brightBlack: "#586e75",
        brightRed: "#cb4b16",
        brightGreen: "#586e75",
        brightYellow: "#657b83",
        brightBlue: "#839496",
        brightMagenta: "#6c71c4",
        brightCyan: "#93a1a1",
        brightWhite: "#fdf6e3"
    )

    /// Solarized Light — the light variant of Solarized.
    static let solarizedLight = TerminalTheme(
        id: "solarized-light",
        name: "Solarized Light",
        background: "#fdf6e3",
        foreground: "#657b83",
        cursor: "#586e75",
        cursorAccent: "#fdf6e3",
        selectionBackground: "#eee8d5",
        black: "#073642",
        red: "#dc322f",
        green: "#859900",
        yellow: "#b58900",
        blue: "#268bd2",
        magenta: "#d33682",
        cyan: "#2aa198",
        white: "#eee8d5",
        brightBlack: "#002b36",
        brightRed: "#cb4b16",
        brightGreen: "#586e75",
        brightYellow: "#657b83",
        brightBlue: "#839496",
        brightMagenta: "#6c71c4",
        brightCyan: "#93a1a1",
        brightWhite: "#fdf6e3"
    )

    /// Monokai — the classic Sublime Text / TextMate theme.
    static let monokai = TerminalTheme(
        id: "monokai",
        name: "Monokai",
        background: "#272822",
        foreground: "#f8f8f2",
        cursor: "#f8f8f0",
        cursorAccent: "#272822",
        selectionBackground: "#49483e80",
        black: "#272822",
        red: "#f92672",
        green: "#a6e22e",
        yellow: "#f4bf75",
        blue: "#66d9ef",
        magenta: "#ae81ff",
        cyan: "#a1efe4",
        white: "#f8f8f2",
        brightBlack: "#75715e",
        brightRed: "#f92672",
        brightGreen: "#a6e22e",
        brightYellow: "#f4bf75",
        brightBlue: "#66d9ef",
        brightMagenta: "#ae81ff",
        brightCyan: "#a1efe4",
        brightWhite: "#f9f8f5"
    )

    /// Nord — Arctic, north-bluish clean and elegant palette.
    static let nord = TerminalTheme(
        id: "nord",
        name: "Nord",
        background: "#2e3440",
        foreground: "#d8dee9",
        cursor: "#d8dee9",
        cursorAccent: "#2e3440",
        selectionBackground: "#434c5e80",
        black: "#3b4252",
        red: "#bf616a",
        green: "#a3be8c",
        yellow: "#ebcb8b",
        blue: "#81a1c1",
        magenta: "#b48ead",
        cyan: "#88c0d0",
        white: "#e5e9f0",
        brightBlack: "#4c566a",
        brightRed: "#bf616a",
        brightGreen: "#a3be8c",
        brightYellow: "#ebcb8b",
        brightBlue: "#81a1c1",
        brightMagenta: "#b48ead",
        brightCyan: "#8fbcbb",
        brightWhite: "#eceff4"
    )
}
