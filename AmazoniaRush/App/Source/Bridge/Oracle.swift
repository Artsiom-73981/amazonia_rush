import Foundation

/// Writes a request payload in the byte order the oracle expects.
struct Quill {
    private(set) var bytes: [UInt8] = []

    mutating func byte(_ value: UInt8) { bytes.append(value) }
    mutating func flag(_ value: Bool) { bytes.append(value ? 1 : 0) }

    mutating func pair(_ value: UInt16) {
        withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
    }

    mutating func quad(_ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
    }

    mutating func signed(_ value: Int32) {
        withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
    }

    mutating func octet(_ value: UInt64) {
        withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
    }

    mutating func ratio(_ value: Float) {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { bytes.append(contentsOf: $0) }
    }

    static func of(quad value: UInt32) -> [UInt8] {
        var quill = Quill()
        quill.quad(value)
        return quill.bytes
    }

    static func of(pair value: UInt16) -> [UInt8] {
        var quill = Quill()
        quill.pair(value)
        return quill.bytes
    }
}

/// Reads a response frame. Running past the end yields zeroes rather than
/// trapping, so a protocol mismatch degrades instead of crashing the game.
struct Scroll {
    private let slab: [UInt8]
    private var head: Int
    let version: UInt8
    let dirty: Bool
    let echo: UInt32

    init(_ slab: [UInt8]) {
        self.slab = slab
        var cursor = 0
        func grab(_ span: Int) -> [UInt8] {
            let start = min(cursor, slab.count)
            let stop = min(cursor + span, slab.count)
            cursor = stop
            return Array(slab[start..<stop])
        }
        version = grab(1).first ?? 0
        dirty = (grab(1).first ?? 0) != 0
        let tag = grab(4)
        echo = tag.count == 4
            ? UInt32(tag[0]) | UInt32(tag[1]) << 8 | UInt32(tag[2]) << 16 | UInt32(tag[3]) << 24
            : 0
        head = cursor
    }

    private mutating func take(_ span: Int) -> ArraySlice<UInt8> {
        let start = min(head, slab.count)
        let stop = min(head + span, slab.count)
        head = stop
        return slab[start..<stop]
    }

    /// Bytes not yet read. A healthy decode leaves zero.
    var leftover: Int { max(0, slab.count - head) }

    mutating func byte() -> UInt8 { take(1).first ?? 0 }
    mutating func flag() -> Bool { byte() != 0 }

    mutating func pair() -> UInt16 {
        let raw = Array(take(2))
        guard raw.count == 2 else { return 0 }
        return UInt16(raw[0]) | UInt16(raw[1]) << 8
    }

    mutating func quad() -> UInt32 {
        let raw = Array(take(4))
        guard raw.count == 4 else { return 0 }
        return UInt32(raw[0]) | UInt32(raw[1]) << 8 | UInt32(raw[2]) << 16 | UInt32(raw[3]) << 24
    }

    mutating func signed() -> Int32 { Int32(bitPattern: quad()) }

    mutating func octet() -> UInt64 {
        var value: UInt64 = 0
        let raw = Array(take(8))
        guard raw.count == 8 else { return 0 }
        for (shift, piece) in raw.enumerated() {
            value |= UInt64(piece) << (8 * shift)
        }
        return value
    }

    mutating func ratio() -> Float { Float(bitPattern: quad()) }

    mutating func tally() -> Int { Int(pair()) }

    mutating func run() -> [UInt8] {
        let span = Int(pair())
        return Array(take(span))
    }

    mutating func count() -> Int { Int(quad()) }

    /// Convenience for the purse block every snapshot starts with.
    mutating func purse() -> Purse {
        Purse(
            shards: octet(),
            cores: octet(),
            resin: octet(),
            seals: octet(),
            shardCeiling: octet()
        )
    }
}

struct Purse {
    var shards: UInt64 = 0
    var cores: UInt64 = 0
    var resin: UInt64 = 0
    var seals: UInt64 = 0
    var shardCeiling: UInt64 = 1

    func amount(at slot: Int) -> UInt64 {
        switch slot {
        case 0: return shards
        case 1: return cores
        case 2: return resin
        default: return seals
        }
    }
}

/// Keeps the sealed profile on disk. The blob is produced and verified by the
/// oracle, so this type only moves bytes.
final class Keeper {
    private let scrollPath: URL

    init() {
        let home = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        // Name derived at runtime: no readable file name in the binary.
        scrollPath = home.appendingPathComponent(Vault.scrollLeaf())
    }

    func read() -> [UInt8] {
        guard let data = try? Data(contentsOf: scrollPath) else { return [] }
        return [UInt8](data)
    }

    func write(_ blob: [UInt8]) {
        guard !blob.isEmpty else { return }
        let swap = scrollPath.appendingPathExtension("swap")
        do {
            try Data(blob).write(to: swap, options: .atomic)
            _ = try? FileManager.default.replaceItemAt(scrollPath, withItemAt: swap)
        } catch {
            try? Data(blob).write(to: scrollPath, options: .atomic)
        }
    }

    func erase() {
        try? FileManager.default.removeItem(at: scrollPath)
    }
}

/// The single door to the native oracle. Every rule the game obeys comes back
/// through `ask`.
final class Oracle {
    static let shared = Oracle()

    private var handle: OpaquePointer?
    private let keeper = Keeper()
    private var sealPending = false

    private init() {}

    func awaken() {
        guard handle == nil else { return }
        let blob = keeper.read()
        let tongue = Tongue.ofDevice
        handle = blob.withUnsafeBufferPointer { buffer in
            vr_awaken(buffer.baseAddress, blob.count, tongue)
        }
    }

    /// One descent frame. Most descent calls answer with a leading verdict
    /// flag before the snapshot; `verdict` says whether to read it.
    func descend(_ op: UInt32, _ body: [UInt8] = [], verdict: Bool = true) -> (Bool, DelveView) {
        var scroll = ask(op, body)
        let allowed = verdict ? scroll.flag() : true
        return (allowed, DelveView(&scroll))
    }

    func ask(_ op: UInt32, _ body: [UInt8] = []) -> Scroll {
        guard let handle else { return Scroll([]) }
        var span = 0
        let frame: UnsafeMutablePointer<UInt8>? = body.withUnsafeBufferPointer { buffer in
            vr_relay(handle, op, buffer.baseAddress, body.count, &span)
        }
        guard let frame, span > 0 else { return Scroll([]) }
        let slab = Array(UnsafeBufferPointer(start: frame, count: span))
        vr_reclaim(frame, span)
        let scroll = Scroll(slab)
        if scroll.dirty { sealPending = true }
        return scroll
    }

    /// Persists the profile when the oracle says something changed.
    func preserve(force: Bool = false) {
        guard handle != nil, sealPending || force else { return }
        var scroll = ask(Rite.saveBlob)
        let blob = scroll.run()
        if !blob.isEmpty {
            keeper.write(blob)
            sealPending = false
        }
    }

    func wipeScroll() {
        _ = ask(Rite.wipe)
        keeper.erase()
        preserve(force: true)
    }

    func heartbeat() -> Scroll {
        var quill = Quill()
        quill.octet(UInt64(bitPattern: Int64(Date().timeIntervalSince1970)))
        quill.signed(Int32(TimeZone.current.secondsFromGMT() / 60))
        return ask(Rite.heartbeat, quill.bytes)
    }
}

/// Request numbers. Mirrors `rite` in the Rust crate.
enum Rite {
    static let heartbeat: UInt32 = 1
    static let hub: UInt32 = 2
    static let map: UInt32 = 3
    static let delveOpen: UInt32 = 4
    static let delveAct: UInt32 = 5
    static let delveKnack: UInt32 = 6
    static let delvePress: UInt32 = 7
    static let delveBoon: UInt32 = 8
    static let delveFork: UInt32 = 9
    static let delveTrade: UInt32 = 10
    static let delveAbandon: UInt32 = 11
    static let delveView: UInt32 = 12
    static let lattice: UInt32 = 13
    static let latticeBuy: UInt32 = 14
    static let cadre: UInt32 = 15
    static let scarabRank: UInt32 = 16
    static let scarabDeploy: UInt32 = 17
    static let powerAssign: UInt32 = 18
    static let relics: UInt32 = 19
    static let forge: UInt32 = 20
    static let forgeMake: UInt32 = 21
    static let caravan: UInt32 = 22
    static let caravanTrade: UInt32 = 23
    static let skinWear: UInt32 = 24
    static let rites: UInt32 = 25
    static let riteClaim: UInt32 = 26
    static let ascent: UInt32 = 27
    static let ascentClaim: UInt32 = 28
    static let edicts: UInt32 = 29
    static let edictClaim: UInt32 = 30
    static let edictReroll: UInt32 = 31
    static let chronicleClaim: UInt32 = 32
    static let medals: UInt32 = 33
    static let codex: UInt32 = 34
    static let records: UInt32 = 35
    static let switchSet: UInt32 = 36
    static let tutorSet: UInt32 = 37
    static let wipe: UInt32 = 38
    static let reawaken: UInt32 = 39
    static let saveBlob: UInt32 = 40
    static let text: UInt32 = 41
    static let textSpan: UInt32 = 42
}

/// Settings bit flags. Mirrors `toggle` in the Rust crate.
enum Switch {
    static let sound: UInt32 = 1 << 0
    static let music: UInt32 = 1 << 1
    static let haptics: UInt32 = 1 << 2
    static let hints: UInt32 = 1 << 3
    static let leftHand: UInt32 = 1 << 4
    static let gore: UInt32 = 1 << 6
    static let bold: UInt32 = 1 << 5
    static let pushAsked: UInt32 = 1 << 6
}

/// Which compiled language the core should speak. The scroll order is fixed
/// by the forge: English first, Russian second.
enum Tongue {
    static var ofDevice: UInt8 {
        let tag = Locale.preferredLanguages.first ?? "en"
        return tag.hasPrefix("ru") ? 1 : 0
    }
}
