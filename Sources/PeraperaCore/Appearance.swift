import Foundation

/// Light, dark, or whatever the system says.
///
/// Solarized has a real light mode and a real dark mode, not one derived from
/// the other, and which reads better depends on the room rather than on the time
/// of day the system switched at. Following the system is the default, not the
/// only option.
public enum Appearance: String, CaseIterable, Codable, Sendable, Identifiable {
    case system, light, dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: "Match system"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// Whether to use the dark palette, given what the system currently says.
    public func isDark(systemIsDark: Bool) -> Bool {
        switch self {
        case .system: systemIsDark
        case .light: false
        case .dark: true
        }
    }
}
