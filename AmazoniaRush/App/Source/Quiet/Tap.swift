import Foundation

/// The hand-off between a cold-start push and the boot screen. The scene
/// delegate writes the tapped address here before the app has a view; the
/// boot path reads it first, before anything else is decided, so the address
/// is never lost to a race with the network or the gate.
enum Tap {
    /// A single derived account name shared by the writer (the scene/app
    /// delegate) and the reader (the boot path). The stashed value is a partner
    /// address, so it lives in the keychain rather than a readable defaults file,
    /// even though it is only there for the moment between a tap and the boot.
    private static let key = "tap." + "quiet.route"

    static func stash(_ address: String) {
        Keyring.write(key, address)
    }

    /// Reads and clears in one move: a pushed destination is one-shot.
    static func consume() -> String? {
        guard let value = Keyring.read(key), !value.isEmpty else { return nil }
        Keyring.write(key, nil)
        return value
    }

    /// Pulls an address out of a push payload, wherever the sender put it.
    /// Senders vary, so every shape the contract allows is tried.
    static func deepLink(in payload: [AnyHashable: Any]) -> String? {
        let shapes = ["url", "link", "target", "deeplink", "deep_link"]
        let nests: [[AnyHashable: Any]] = [
            payload,
            payload["data"] as? [AnyHashable: Any] ?? [:],
            payload["payload"] as? [AnyHashable: Any] ?? [:],
            (payload["aps"] as? [AnyHashable: Any])?["data"] as? [AnyHashable: Any] ?? [:],
        ]
        for nest in nests {
            for shape in shapes {
                if let found = nest[shape] as? String, !found.isEmpty { return found }
            }
        }
        return nil
    }
}
