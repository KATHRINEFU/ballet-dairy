import SwiftUI
import UIKit

/// Ballet-core palette: cream paper, plum ink, satin and ribbon pinks, a whisper of lilac.
enum Theme {
    // Paper & ink
    static let paper = Color(hex: 0xFBF6F0)
    static let paperDeep = Color(hex: 0xF3EAE2)
    static let rule = Color(hex: 0xEADCD6)
    static let margin = Color(hex: 0xEDB3BE)
    static let ink = Color(hex: 0x3A2E35)
    static let inkSoft = Color(hex: 0x86737B)
    static let inkFaint = Color(hex: 0xB9A9AF)

    // Ballet core
    static let satin = Color(hex: 0xF8E5E4)
    static let blush = Color(hex: 0xF3D0D5)
    static let rose = Color(hex: 0xE69CAC)
    static let ribbon = Color(hex: 0xC5667D)
    static let lilac = Color(hex: 0xCEC4E6)
    static let sage = Color(hex: 0xC8D5C1)
    static let butter = Color(hex: 0xF4E4B8)
    static let gold = Color(hex: 0xC6A46A)

    /// Categorical palette, in fixed slot order (one slot per movement category).
    /// Validated on the paper surface #FBF6F0: lightness band, chroma floor, adjacent CVD ΔE ≥ 8 and
    /// normal-vision ΔE ≥ 15 all pass; slot 3 (amber) is < 3:1 contrast, so charts always pair colour with
    /// visible labels/values.
    static let categoryPalette: [Color] = [
        Color(hex: 0xD24C78), Color(hex: 0x2A78D6), Color(hex: 0xE8962A), Color(hex: 0x159A80),
        Color(hex: 0x7A5BD6), Color(hex: 0x4C9A22), Color(hex: 0xC04A9A), Color(hex: 0xE26A3A), Color(hex: 0x2F5F9E),
    ]

    static func categoryColor(_ id: String) -> Color {
        let order = ["positions", "port_de_bras", "barre", "center", "turns", "petit_allegro", "grand_allegro", "linking", "pointe"]
        let i = order.firstIndex(of: id) ?? abs(id.hashValue) % categoryPalette.count
        return categoryPalette[i % categoryPalette.count]
    }

    // MARK: Type
    /// Editorial serif — titles, French names.
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif).italic()
    }
    /// Handwriting — diary text, annotations.
    static func hand(_ size: CGFloat) -> Font { .custom("Noteworthy-Light", size: size) }
    static func handBold(_ size: CGFloat) -> Font { .custom("Noteworthy-Bold", size: size) }
    /// Script — a single flourish per screen, never for body text.
    static func script(_ size: CGFloat) -> Font { .custom("SnellRoundhand-Bold", size: size) }
    /// Small caps label.
    static func label(_ size: CGFloat = 11) -> Font { .system(size: size, weight: .semibold, design: .rounded) }

    static let handUIFont = UIFont(name: "Noteworthy-Light", size: 18) ?? .systemFont(ofSize: 18)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

// MARK: - Surfaces

extension View {
    /// A paper card: content lives on paper; Liquid Glass is reserved for the floating, interactive layer.
    func paperCard(cornerRadius: CGFloat = 28, padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.62))
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.rule, lineWidth: 0.8))
                    .shadow(color: Theme.ink.opacity(0.05), radius: 14, y: 6)
            }
    }

    /// Small caps tracking label used for section eyebrows.
    func eyebrow() -> some View {
        self.font(Theme.label(11)).textCase(.uppercase).tracking(1.6).foregroundStyle(Theme.inkSoft)
    }
}
