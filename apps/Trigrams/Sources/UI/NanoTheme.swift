import AppKit
import CoreText
import SwiftUI

struct NanoPalette {
    let isDark: Bool
    var background: Color { color("FFFFFF", "2E3440") }
    var foreground: Color { color("37474F", "ECEFF4") }
    var highlight: Color { color("FAFAFA", "3B4252") }
    var subtle: Color { color("ECEFF1", "434C5E") }
    var salient: Color { color("673AB7", "81A1C1") }
    var strong: Color { color("000000", "ECEFF4") }
    var critical: Color { color("FF6F00", "EBCB8B") }
    var popout: Color { color("FFAB91", "D08770") }
    var faded: Color { color("B0BEC5", "677691") }
    var secondary: Color { color("586C76", "B9C3D3") }
    var accentText: Color { color("673AB7", "AFC3DC") }
    var warningText: Color { color("9A4600", "EBCB8B") }
    var errorText: Color { color("B23A32", "E28A8F") }
    var successText: Color { color("28704B", "A3BE8C") }
    var actionForeground: Color { color("FFFFFF", "2E3440") }
    // A required input border uses the readable secondary color, not faded.
    var inputBorder: Color { secondary.opacity(0.8) }
    private func color(_ light: String, _ dark: String) -> Color { Color(hex: isDark ? dark : light) }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = NanoPalette(isDark: false)
}

extension EnvironmentValues {
    var nanoPalette: NanoPalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension Color {
    init(hex: String) {
        let value = UInt32(hex, radix: 16) ?? 0
        self.init(.sRGB, red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255, opacity: 1)
    }
}

enum TrigramsFont {
    static func body(_ size: CGFloat = 14) -> Font { .custom("InterVariable", size: size, relativeTo: .body) }
    static func medium(_ size: CGFloat = 14) -> Font { body(size).weight(.medium) }
    static func code(_ size: CGFloat = 13) -> Font { .system(size: size, design: .monospaced) }
    @MainActor static func register() {
        let url = Bundle.main.url(forResource: "InterVariable", withExtension: "ttf", subdirectory: "Fonts") ?? Bundle.main.url(forResource: "InterVariable", withExtension: "ttf")
        if let url { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    }
}
