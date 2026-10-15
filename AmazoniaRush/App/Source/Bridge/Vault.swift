import UIKit

/// Everything textual in the game passes through here. Nothing readable is
/// stored in the executable: UI copy lives as ciphertext inside the oracle and
/// asset names live as cloaked byte rows next door.
enum Vault {
    private static var phrases: [UInt16: String] = [:]
    private static var artworks: [Int: UIImage] = [:]
    private static var plates: [Int: UIImage] = [:]
    private static var sceneCache: [Int: UIImage] = [:]

    // --- copy --------------------------------------------------------------

    static func say(_ lexeme: UInt16) -> String {
        if let known = phrases[lexeme] { return known }
        var scroll = Oracle.shared.ask(Rite.text, Quill.of(pair: lexeme))
        let raw = scroll.run()
        let text = String(decoding: raw)
        // Nothing comes back before the core is awake, and an empty answer
        // must never be remembered as the real wording.
        if !text.isEmpty { phrases[lexeme] = text }
        return text
    }

    /// Fills the cache in one sweep so later screens never wait on the bridge.
    static func learnAll() {
        var scroll = Oracle.shared.ask(Rite.textSpan)
        let span = scroll.count()
        guard span > 0 else { return }
        phrases.reserveCapacity(span)
        for lexeme in 0..<span {
            _ = say(UInt16(lexeme))
        }
    }

    // --- cloaked names -----------------------------------------------------

    private static func uncloak(_ row: [UInt8], _ salt: Int) -> String {
        var drum = UInt8(truncatingIfNeeded: salt * 131 + 7)
        var clear: [UInt8] = []
        clear.reserveCapacity(row.count)
        for (index, piece) in row.enumerated() {
            drum = UInt8(truncatingIfNeeded: Int(drum) * 31 + index * 17 + 91)
            clear.append(piece ^ drum)
        }
        return String(decoding: clear)
    }

    static func sceneLeaf(_ index: Int) -> String {
        let table = Canvas.sceneNames
        guard table.indices.contains(index) else { return "" }
        return uncloak(table[index], 0x11 + index)
    }

    static func propLeaf(_ index: Int) -> String {
        let table = Canvas.propNames
        guard table.indices.contains(index) else { return "" }
        return uncloak(table[index], 0x53 + index)
    }

    static func cueLeaf(_ index: Int) -> String {
        let table = Canvas.cueNames
        guard table.indices.contains(index) else { return "" }
        return uncloak(table[index], 0x97 + index)
    }

    static func plateLeaf(_ index: Int) -> String {
        let table = Canvas.plateNames
        guard table.indices.contains(index) else { return "" }
        return uncloak(table[index], 0xC1 + index)
    }

    /// The save file name, assembled at runtime from cloaked parts.
    static func scrollLeaf() -> String {
        uncloak([91, 120, 126, 27, 134, 131, 211, 19, 240, 255, 39, 39, 68, 223, 147, 64], 0x07)
    }

    // --- artwork -----------------------------------------------------------

    static func prop(_ index: Int) -> UIImage? {
        if let known = artworks[index] { return known }
        guard let found = UIImage(named: propLeaf(index)) else { return nil }
        artworks[index] = found
        return found
    }

    static func scene(_ index: Int) -> UIImage? {
        if let known = sceneCache[index] { return known }
        guard let found = UIImage(named: sceneLeaf(index)) else { return nil }
        if sceneCache.count > 4 { sceneCache.removeAll(keepingCapacity: true) }
        sceneCache[index] = found
        return found
    }

    static func plate(_ index: Int) -> UIImage? {
        if let known = plates[index] { return known }
        guard let found = UIImage(named: plateLeaf(index)) else { return nil }
        plates[index] = found
        return found
    }

    static func releaseScenery() {
        sceneCache.removeAll(keepingCapacity: false)
    }
}

extension String {
    /// Avoids `String(decoding:as:)` spelling noise at every call site.
    init(decoding raw: [UInt8]) {
        self = String(bytes: raw, encoding: .utf8) ?? ""
    }
}
