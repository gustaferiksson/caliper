import AppKit
import SwiftUI

extension Color {
    static let defaultMeasurement = Color(hex: "#0A84FF") ?? .blue
    /// The reference keeps its own colour so it stays legible whatever default is chosen.
    static let reference = Color(hex: "#FF9F0A") ?? .orange

    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let packed = UInt32(digits, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((packed >> 16) & 0xFF) / 255,
                  green: Double((packed >> 8) & 0xFF) / 255,
                  blue: Double(packed & 0xFF) / 255)
    }

    var hex: String {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return "#0A84FF" }
        return String(format: "#%02X%02X%02X",
                      Int((srgb.redComponent * 255).rounded()),
                      Int((srgb.greenComponent * 255).rounded()),
                      Int((srgb.blueComponent * 255).rounded()))
    }
}

extension Color {
    /// Selection reads as a darker shade, never a bigger one.
    func darkened(by amount: Double) -> Color {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return self }
        return Color(.sRGB,
                     red: srgb.redComponent * (1 - amount),
                     green: srgb.greenComponent * (1 - amount),
                     blue: srgb.blueComponent * (1 - amount))
    }
}
