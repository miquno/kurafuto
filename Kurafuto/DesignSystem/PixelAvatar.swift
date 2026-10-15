import SwiftUI

/// A Minecraft-style 8×8 face that is always the same for a player name. Drawn locally: loading real skins
/// would need a third-party host, which the privacy rules forbid.
struct PixelAvatar: View {
    let name: String
    var size: CGFloat = 52

    var body: some View {
        let face = PixelFace(name: name)
        Canvas { context, canvas in
            let cell = canvas.width / 8
            for y in 0..<8 {
                for x in 0..<8 {
                    // Slight overlap avoids hairlines between cells.
                    let rect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell + 0.5, height: cell + 0.5)
                    context.fill(Path(rect), with: .color(face.color(x: x, y: y)))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Skin, hair and eye colors and a hair style picked from a stable hash of the name.
struct PixelFace: Equatable {
    let skin: RGB
    let hair: RGB
    let eyes: RGB
    let longHair: Bool
    let beard: Bool

    init(name: String) {
        var hash: UInt64 = 0xcbf29ce484222325 // FNV-1a, stable across launches unlike `hashValue`
        for byte in name.lowercased().utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        func pick<T>(_ list: [T], _ shift: UInt64) -> T { list[Int((hash >> shift) % UInt64(list.count))] }
        skin = pick(Self.skins, 0)
        hair = pick(Self.hairs, 8)
        eyes = pick(Self.eyeColors, 16)
        longHair = (hash >> 24) & 1 == 1
        beard = !longHair && (hash >> 25) & 3 == 0
    }

    func color(x: Int, y: Int) -> Color {
        let edge = x == 0 || x == 7
        let rgb: RGB = switch y {
        case 0, 1: hair
        case 2: edge || (longHair && (x == 1 || x == 6)) ? hair : skin
        case 3: longHair && edge ? hair : skin
        case 4: switch x {
            case 1, 6: RGB(0xF4F4F4)
            case 2, 5: eyes
            default: longHair && edge ? hair : skin
            }
        case 5: x == 3 || x == 4 ? skin.shaded(0.8) : skin
        case 6: (beard && (2...5).contains(x)) ? hair : (x == 3 || x == 4 ? skin.shaded(0.62) : skin)
        default: beard && (1...6).contains(x) ? hair : skin.shaded(0.92)
        }
        return rgb.color
    }

    struct RGB: Equatable {
        let r, g, b: Double
        init(_ hex: UInt32) {
            r = Double((hex >> 16) & 0xFF) / 255
            g = Double((hex >> 8) & 0xFF) / 255
            b = Double(hex & 0xFF) / 255
        }
        private init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
        func shaded(_ factor: Double) -> RGB { RGB(r: r * factor, g: g * factor, b: b * factor) }
        var color: Color { Color(red: r, green: g, blue: b) }
    }

    // Player art, not interface color: the faces look the same in every theme.
    private static let skins = ([0xF2C9A0, 0xE0AC7E, 0xC68642, 0x8D5524, 0xF5D7C4, 0xD8A47F] as [UInt32]).map(RGB.init)
    private static let hairs = ([0x3B2A1A, 0x6B4423, 0xD9A441, 0xB5502A, 0x1F1F22, 0xA0A0A8, 0xE8E0D0, 0x2E4A7A] as [UInt32]).map(RGB.init)
    private static let eyeColors = ([0x3B5BA9, 0x2E7D32, 0x5D4037, 0x455A64, 0x6A1B9A] as [UInt32]).map(RGB.init)
}

#Preview {
    HStack { ForEach(["Steve_DE", "miquno", "Alex2010", "MasterBuilder", "PocketHero"], id: \.self) { PixelAvatar(name: $0) } }
        .padding()
}
