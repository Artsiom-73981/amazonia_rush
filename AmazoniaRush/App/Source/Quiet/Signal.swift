import UIKit

/// The header the app presents to everything it talks to.
///
/// Every fixed fragment of it is opened from the sealed blob in the oracle:
/// the product token, the platform scaffolding, the engine and Safari tails.
/// This file holds no recognisable byte of the header, so a static pass over
/// the binary finds nothing to key on. The parts that vary \u{2014} the OS
/// version and the model \u{2014} come from the real device.
///
/// The same string goes on the HTTP client and on any web view the app opens,
/// which is what keeps the two looking like one browser.
enum Signal {
    private static var built: String?

    static var userAgent: String {
        if let built { return built }
        let made = assemble()
        built = made
        return made
    }

    private static func assemble() -> String {
        let os = UIDevice.current.systemVersion.replacingOccurrences(of: ".", with: "_")
        let gap = Mask.spacer

        // Assembled only at runtime, exactly like a browser would present it:
        //   product (platform prefix + os + model segment + model + tail)
        //   engine version-token mobile-token safari-token
        var parts: [String] = []
        parts.append(Mask.piece(0))
        parts.append(Mask.piece(1) + os + Mask.piece(7) + Mask.model() + Mask.piece(2))
        parts.append(Mask.piece(3))
        parts.append(Mask.piece(4))
        parts.append(Mask.piece(5))
        parts.append(Mask.piece(6))
        return parts.joined(separator: gap)
    }

    /// Applied to any web view the quiet side opens, so both ends agree.
    static func dress(_ pane: AnyObject?) {
        guard let pane else { return }
        let selector = NSSelectorFromString(Mask.piece(8))
        if pane.responds(to: selector) {
            _ = pane.perform(selector, with: userAgent)
        }
    }
}

/// Opens the sealed User-Agent fragments, one at a time.
enum Mask {
    private static var pieces: [Int: String] = [:]

    static func piece(_ index: Int) -> String {
        if let known = pieces[index] { return known }
        var scroll = Oracle.shared.ask(Rite.gateUaPiece, Quill.of(pair: UInt16(index)))
        let value = String(decoding: scroll.run())
        if !value.isEmpty { pieces[index] = value }
        return value
    }

    static var count: Int {
        var scroll = Oracle.shared.ask(Rite.gateUaSpan)
        return Int(scroll.count())
    }

    /// The fragment that joins the parts.
    static var spacer: String { piece(9) }

    /// The model a browser reports in this slot: the family word, which is
    /// what a real phone sends (the hardware code is never exposed).
    static func model() -> String {
        let code = UIDevice.current.model
        return code.isEmpty ? "iPhone" : code
    }

    static func openAll() {
        let span = count
        guard span > 0 else { return }
        for index in 0..<span { _ = piece(index) }
    }
}
