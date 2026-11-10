import Foundation
import Network

/// Answers one question only: is there a route to the internet right now?
/// The quiet side asks before it tries to reach the backend, so a player with
/// no connection sees the no-connection screen promptly rather than waiting
/// out a request timeout.
final class Gauge {
    static let shared = Gauge()

    private let watch = NWPathMonitor()
    private let queue = DispatchQueue(label: "reach.watch")
    private var open = false
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        watch.pathUpdateHandler = { [weak self] path in
            self?.open = path.status == .satisfied
        }
        watch.start(queue: queue)
    }

    /// True when a route exists. Optimistic before the first update lands, so
    /// a freshly launched app is never blocked by an unstarted monitor.
    var live: Bool {
        start()
        return open
    }

    /// Waits briefly for a route rather than reading a stale answer, which is
    /// what makes the retry button feel immediate.
    func settle(_ span: TimeInterval = 0.9, then: @escaping (Bool) -> Void) {
        start()
        if open { then(true); return }
        let deadline = Date().addingTimeInterval(span)
        func peek() {
            if open || Date() >= deadline {
                then(open)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: peek)
        }
        peek()
    }
}

/// A direct reachability probe. Used as a second opinion when the path monitor
/// is optimistic but a request still fails, which happens on captive portals.
enum Beacon {
    static func resolves(_ host: String) -> Bool {
        guard !host.isEmpty else { return false }
        var hints = addrinfo(
            ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM,
            ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil,
            ai_next: nil
        )
        var head: UnsafeMutablePointer<addrinfo>?
        let outcome = getaddrinfo(host, nil, &hints, &head)
        if let head { freeaddrinfo(head) }
        return outcome == 0
    }

    /// The bare host of a sealed address, for the probe above.
    static func host(of address: String) -> String {
        guard let parts = URL(string: address), let host = parts.host else { return "" }
        return host
    }
}
