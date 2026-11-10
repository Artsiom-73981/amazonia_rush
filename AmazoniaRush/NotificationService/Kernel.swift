import Foundation

/// The smallest possible door to the core, for the extension.
///
/// The game's bridge carries the whole protocol; this needs one opcode and
/// the two globals it talks to, so it stays small and independent of any
/// screen.
enum Kernel {
    private static var handle: OpaquePointer?

    static func awaken() {
        guard handle == nil else { return }
        handle = vr_awaken(nil, 0, 0)
    }

    /// Opens every slot in one sweep, so the act of reading one later never
    /// pays for the cipher more than once.
    static func warm() {
        awaken()
        for which in 0..<UInt16(13) { _ = slot(which) }
    }

    /// Opens a sealed slot by number and returns its text.
    static func slot(_ which: UInt16) -> String {
        guard let handle else { return "" }
        var body = [UInt8]()
        body.append(UInt8(truncatingIfNeeded: which))
        body.append(UInt8(truncatingIfNeeded: which >> 8))
        var span = 0
        let frame: UnsafeMutablePointer<UInt8>? = body.withUnsafeBufferPointer { buffer in
            vr_relay(handle, 43, buffer.baseAddress, body.count, &span)
        }
        guard let frame, span > 0 else { return "" }
        let slab = Array(UnsafeBufferPointer(start: frame, count: span))
        vr_reclaim(frame, span)
        guard slab.count > 6 else { return "" }
        // The frame opens with a version byte, a dirty flag and the echoed
        // opcode; the value follows as a length-prefixed run.
        let head = 6
        let length = min(Int(slab[head]) | Int(slab[head + 1]) << 8, slab.count - head - 2)
        let run = Array(slab[(head + 2)..<(head + 2 + length)])
        return String(decoding: run, as: UTF8.self)
    }
}
