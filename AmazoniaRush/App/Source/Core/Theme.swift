import UIKit

/// Palette and metrics. Hand-mixed so the game does not look like a template.
enum Hide {
    /// Blood, three shades of it: fresh, darker, and what dries on stone.
    static func gore(_ depth: Int) -> UIColor {
        switch depth {
        case 0: return ink(168, 28, 24)
        case 1: return ink(126, 18, 18)
        default: return ink(78, 12, 14)
        }
    }

    static func ink(_ red: Int, _ green: Int, _ blue: Int, _ veil: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: veil
        )
    }

    static let pitch = ink(10, 14, 12)
    static let loam = ink(22, 29, 24)
    static let slate = ink(33, 42, 36)
    static let plinth = ink(44, 54, 45)
    static let brass = ink(206, 162, 74)
    static let brassDim = ink(138, 106, 48)
    static let gild = ink(246, 214, 136)
    static let parchment = ink(238, 229, 205)
    static let murmur = ink(176, 170, 149)
    static let hush = ink(126, 122, 108)
    static let ember = ink(226, 120, 58)
    static let verdure = ink(104, 176, 118)
    static let lapis = ink(84, 142, 212)
    static let bruise = ink(190, 72, 84)
    static let violetDusk = ink(150, 104, 196)

    /// Ember colours by hue index, matching the oracle's four streams.
    static let streams: [UIColor] = [
        ink(238, 176, 64),
        ink(96, 186, 214),
        ink(196, 96, 190),
        ink(126, 206, 108),
    ]

    static func stream(_ hue: UInt8) -> UIColor {
        streams[Int(hue) % streams.count]
    }

    /// Enemy tints, one per breed.
    static func hide(of breed: UInt8) -> UIColor {
        switch breed {
        case Breed.jackal: return ink(214, 148, 72)
        case Breed.spitter: return ink(126, 190, 110)
        case Breed.hopper: return ink(120, 170, 214)
        case Breed.warden: return ink(196, 108, 96)
        case Breed.brooder: return ink(178, 120, 200)
        case Breed.sentinel: return ink(150, 150, 164)
        case Breed.revenant: return ink(232, 96, 96)
        default: return ink(186, 176, 150)
        }
    }
}

enum Scribe {
    /// A flat serif face: closer to carved stone than the default UI font.
    static func carved(_ size: CGFloat, _ heft: UIFont.Weight = .semibold) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: heft)
        guard let shaped = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: shaped, size: size)
    }

    static func plain(_ size: CGFloat, _ heft: UIFont.Weight = .regular) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: heft)
    }

    static func tally(_ size: CGFloat) -> UIFont {
        UIFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
    }
}

/// One spacing scale for the whole game. Every screen uses these and nothing
/// else, which is what keeps panels from crowding each other.
enum Grid {
    /// Page margin, left and right.
    static let gutter: CGFloat = 18
    /// Space between two cards in a list.
    static let gap: CGFloat = 12
    /// Space between a card and its own contents.
    static let inset: CGFloat = 14
    /// The smallest gap worth having: a label and the line under it.
    static let tight: CGFloat = 6
    static let corner: CGFloat = 16
    static let rail: CGFloat = 54
    /// Smallest comfortable tap target.
    static let touch: CGFloat = 44
    static let tile: CGFloat = 2
}

/// Number shaping. Big values get a short suffix so the HUD never overflows.
enum Digits {
    private static let suffixes: [Character] = ["k", "m", "b", "t"]

    static func brief(_ value: UInt64) -> String {
        if value < 10_000 { return "\(value)" }
        var scaled = Double(value)
        var step = -1
        while scaled >= 1000 && step < suffixes.count - 1 {
            scaled /= 1000
            step += 1
        }
        let digits = scaled < 10 ? 2 : (scaled < 100 ? 1 : 0)
        var text = String(format: "%.\(digits)f", scaled)
        while text.contains(".") && (text.hasSuffix("0") || text.hasSuffix(".")) {
            text.removeLast()
        }
        return text + String(suffixes[max(0, step)])
    }

    static func brief(_ value: UInt32) -> String { brief(UInt64(value)) }
    static func brief(_ value: Int) -> String { brief(UInt64(max(0, value))) }

    /// Countdown for the dawn timer, rendered without a formatter.
    static func clockFace(_ seconds: UInt64) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let rest = seconds % 60
        func pad(_ piece: UInt64) -> String { piece < 10 ? "0\(piece)" : "\(piece)" }
        if hours > 0 { return "\(hours):\(pad(minutes)):\(pad(rest))" }
        return "\(pad(minutes)):\(pad(rest))"
    }
}
