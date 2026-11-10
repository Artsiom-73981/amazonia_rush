import Foundation

/// The quiet side's addresses and keys, read out of the sealed blob in the
/// oracle one slot at a time. No literal worth hiding ever sits in this file:
/// the numbers below are slot handles, not values.
enum Cap {
    /// Slot handles. Mirrors `slot` in the Rust gate module; the order is
    /// fixed by the forge.
    enum Slot: UInt16 {
        case endpoint = 0
        case privacy = 1
        case support = 2
        case attributionKey = 3
        case sender = 4
        case bundle = 5
        case store = 6
        case title = 7
        case nseSuffix = 8
        // The Firebase identity, which is why no GoogleService-Info.plist
        // exists in this bundle.
        case fbApiKey = 9
        case fbProject = 10
        case fbBucket = 11
        case fbAppId = 12
    }

    private static var cache: [UInt16: String] = [:]

    /// Opens one slot. An empty answer means the core is not awake yet, so it
    /// is never remembered as the real value.
    static func text(_ slot: Slot) -> String {
        if let known = cache[slot.rawValue] { return known }
        var scroll = Oracle.shared.ask(Rite.gateSlot, Quill.of(pair: slot.rawValue))
        let value = String(decoding: scroll.run())
        if !value.isEmpty { cache[slot.rawValue] = value }
        return value
    }

    /// Warms every slot in one sweep so the boot path never waits mid-decision.
    static func openAll() {
        var scroll = Oracle.shared.ask(Rite.gateSpan)
        let span = scroll.count()
        guard span > 0 else { return }
        cache.reserveCapacity(Int(span))
        for handle in 0..<span {
            if let slot = Slot(rawValue: UInt16(handle)) {
                _ = text(slot)
            }
        }
    }

    /// True when the three fields the gate cannot run without are present.
    /// Deliberately does not include the optional links: a missing privacy
    /// page must not stop the app deciding what to show.
    static var ready: Bool {
        !text(.endpoint).isEmpty
            && !text(.attributionKey).isEmpty
            && !text(.sender).isEmpty
    }

    // --- convenience ---------------------------------------------------

    static var endpoint: String { text(.endpoint) }
    static var privacy: String { text(.privacy) }
    static var support: String { text(.support) }
    static var attributionKey: String { text(.attributionKey) }
    static var sender: String { text(.sender) }
    static var bundle: String { text(.bundle) }
    static var store: String { text(.store) }
    static var title: String { text(.title) }
    /// The numeric App Store id, as the config contract wants it.
    static var platformStoreId: String { "id" + text(.store) }
}

// The User-Agent fragments live in Signal.swift, next to the code that joins
// them; this file is only the sealed slot reader.
