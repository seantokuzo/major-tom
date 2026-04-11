import SpriteKit
import SwiftUI

// MARK: - Time of Day

enum TimeOfDay: String, CaseIterable {
    case dawn
    case day
    case dusk
    case night
}

// MARK: - Season

enum Season: String, CaseIterable {
    case spring
    case summer
    case autumn
    case winter
}

// MARK: - Theme Palette

struct ThemePalette {
    /// Color overlay for the scene
    let overlayColor: SKColor
    let overlayAlpha: CGFloat
    /// Window gradient colors
    let windowTop: SKColor
    let windowBottom: SKColor
    /// Monitor glow intensity (0-1)
    let monitorGlow: CGFloat
    /// Whether desk lamps are on
    let lampsOn: Bool
    /// Star field visibility (0-1)
    let starField: CGFloat
}

// MARK: - Seasonal Overlay

struct SeasonalOverlay {
    let tintColor: SKColor
    let tintAlpha: CGFloat
    let plantColor: SKColor
    let showSnow: Bool
    let holiday: Bool
}

// MARK: - Station Alert State

/// Station-wide alert state driven by agent events.
enum StationAlertState: String {
    case normal       // All clear — green status strips
    case attention    // Agent idle >5min or error — yellow strips, subtle pulse
    case alert        // Approval needed — red strips, red haze, strong haptic
    case celebration  // Task completed — blue glow wave
}

// MARK: - Theme Engine

/// Manages station visual themes. In space it's always "night" —
/// the palette is driven by station operational state (alerts) rather than time-of-day.
/// Seasonal overlays kept for holiday decorations.
@Observable
final class ThemeEngine {

    // MARK: - State

    private(set) var timeOfDay: TimeOfDay = .night
    private(set) var season: Season = .spring
    private(set) var palette: ThemePalette = ThemeEngine.nightPalette
    private(set) var seasonal: SeasonalOverlay = ThemeEngine.springSeasonal

    /// Current station alert state.
    private(set) var alertState: StationAlertState = .normal

    /// Set the alert state. The scene reads this to update status strips + overlay.
    func setAlertState(_ state: StationAlertState) {
        alertState = state
    }

    /// Color for status strips based on alert state.
    var alertStripColor: SKColor {
        switch alertState {
        case .normal:      return StationPalette.consoleSuccess
        case .attention:   return StationPalette.statusIdle
        case .alert:       return StationPalette.consoleDanger
        case .celebration: return StationPalette.consoleCyan
        }
    }

    /// Overlay tint for alert state.
    var alertOverlayColor: SKColor {
        switch alertState {
        case .normal:      return .clear
        case .attention:   return StationPalette.statusIdle
        case .alert:       return StationPalette.consoleDanger
        case .celebration: return StationPalette.consoleCyan
        }
    }

    /// Overlay alpha for alert state.
    var alertOverlayAlpha: CGFloat {
        switch alertState {
        case .normal:      return 0
        case .attention:   return 0.04
        case .alert:       return 0.08
        case .celebration: return 0.05
        }
    }

    /// Stable star positions (generated once)
    let stars: [(x: CGFloat, y: CGFloat, size: CGFloat, brightness: CGFloat)] = {
        (0..<40).map { _ in
            (
                x: CGFloat.random(in: 0...1),
                y: CGFloat.random(in: 0...1),
                size: CGFloat.random(in: 1...2.5),
                brightness: CGFloat.random(in: 0.3...1.0)
            )
        }
    }()

    private var updateTimer: Timer?

    // MARK: - Palettes

    private static let dawnPalette = ThemePalette(
        overlayColor: SKColor(red: 1.0, green: 0.7, blue: 0.4, alpha: 1),
        overlayAlpha: 0.06,
        windowTop: SKColor(red: 1.0, green: 0.55, blue: 0.24, alpha: 0.5),
        windowBottom: SKColor(red: 1.0, green: 0.78, blue: 0.47, alpha: 0.3),
        monitorGlow: 0.5,
        lampsOn: false,
        starField: 0
    )

    private static let dayPalette = ThemePalette(
        overlayColor: .clear,
        overlayAlpha: 0,
        windowTop: SKColor(red: 0.53, green: 0.78, blue: 1.0, alpha: 0.3),
        windowBottom: SKColor(red: 0.78, green: 0.9, blue: 1.0, alpha: 0.2),
        monitorGlow: 0.3,
        lampsOn: false,
        starField: 0
    )

    private static let duskPalette = ThemePalette(
        overlayColor: SKColor(red: 1.0, green: 0.59, blue: 0.2, alpha: 1),
        overlayAlpha: 0.07,
        windowTop: SKColor(red: 1.0, green: 0.39, blue: 0.2, alpha: 0.5),
        windowBottom: SKColor(red: 1.0, green: 0.63, blue: 0.31, alpha: 0.3),
        monitorGlow: 0.6,
        lampsOn: false,
        starField: 0
    )

    private static let nightPalette = ThemePalette(
        overlayColor: SKColor(red: 0.12, green: 0.16, blue: 0.31, alpha: 1),
        overlayAlpha: 0.12,
        windowTop: SKColor(red: 0.04, green: 0.06, blue: 0.16, alpha: 0.6),
        windowBottom: SKColor(red: 0.08, green: 0.1, blue: 0.2, alpha: 0.5),
        monitorGlow: 1.0,
        lampsOn: true,
        starField: 0.8
    )

    private static let palettes: [TimeOfDay: ThemePalette] = [
        .dawn: dawnPalette,
        .day: dayPalette,
        .dusk: duskPalette,
        .night: nightPalette,
    ]

    // MARK: - Seasonal Overlays

    private static let springSeasonal = SeasonalOverlay(
        tintColor: SKColor(red: 0.39, green: 0.78, blue: 0.39, alpha: 1),
        tintAlpha: 0.03,
        plantColor: SKColor(red: 0.24, green: 0.55, blue: 0.2, alpha: 1),
        showSnow: false,
        holiday: false
    )

    private static let summerSeasonal = SeasonalOverlay(
        tintColor: SKColor(red: 1.0, green: 0.9, blue: 0.59, alpha: 1),
        tintAlpha: 0.03,
        plantColor: SKColor(red: 0.2, green: 0.47, blue: 0.19, alpha: 1),
        showSnow: false,
        holiday: false
    )

    private static let autumnSeasonal = SeasonalOverlay(
        tintColor: SKColor(red: 0.78, green: 0.55, blue: 0.24, alpha: 1),
        tintAlpha: 0.04,
        plantColor: SKColor(red: 0.71, green: 0.47, blue: 0.2, alpha: 1),
        showSnow: false,
        holiday: false
    )

    private static let winterSeasonal = SeasonalOverlay(
        tintColor: SKColor(red: 0.71, green: 0.78, blue: 0.94, alpha: 1),
        tintAlpha: 0.04,
        plantColor: SKColor(red: 0.16, green: 0.31, blue: 0.18, alpha: 1),
        showSnow: true,
        holiday: false
    )

    private static let seasonalOverlays: [Season: SeasonalOverlay] = [
        .spring: springSeasonal,
        .summer: summerSeasonal,
        .autumn: autumnSeasonal,
        .winter: winterSeasonal,
    ]

    // MARK: - Time Calculation

    static func currentTimeOfDay(_ date: Date = Date()) -> TimeOfDay {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let t = Double(hour) + Double(minute) / 60.0
        if t >= 5 && t < 7 { return .dawn }
        if t >= 7 && t < 18 { return .day }
        if t >= 18 && t < 20 { return .dusk }
        return .night
    }

    static func currentSeason(_ date: Date = Date()) -> Season {
        let month = Calendar.current.component(.month, from: date)
        switch month {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }

    static func isHolidaySeason(_ date: Date = Date()) -> Bool {
        Calendar.current.component(.month, from: date) == 12
    }

    // MARK: - Lifecycle

    func start() {
        // Guard against multiple timer starts (SwiftUI .onAppear can re-fire)
        updateTimer?.invalidate()
        updateTimer = nil

        update()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    func stop() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    func update() {
        let now = Date()
        // In space it's always "night" — no day/night cycle
        timeOfDay = .night
        season = Self.currentSeason(now)
        palette = Self.nightPalette

        var s = Self.seasonalOverlays[season] ?? Self.springSeasonal
        if season == .winter && Self.isHolidaySeason(now) {
            s = SeasonalOverlay(
                tintColor: s.tintColor,
                tintAlpha: s.tintAlpha,
                plantColor: s.plantColor,
                showSnow: s.showSnow,
                holiday: true
            )
        }
        seasonal = s
    }
}
