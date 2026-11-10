import Foundation
import Security

/// A tiny keychain drawer for the one thing on the quiet side worth keeping out
/// of a readable preferences file: the address the backend named. Everything
/// else the quiet side remembers is routing bookkeeping, not a partner URL, and
/// stays in `UserDefaults`. Accounts are the same derived, unreadable names the
/// rest of this file uses, so a container dump shows neither a key nor a value.
enum Keyring {
    @discardableResult
    static func write(_ account: String, _ value: String?) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return true }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }
}

/// What the quiet side remembers between launches: which way the app was
/// pointed, the address it was sent to, and when that address stops being
/// worth loading. The address lives in the keychain; the rest is routing
/// bookkeeping kept in defaults, because none of it is the player's progress.
final class Record {
    static let shared = Record()

    private let store = UserDefaults.standard

    /// Which way the app was pointed on the first launch that could decide.
    enum Route: String {
        case undecided
        case quiet
        case native
    }

    private enum Key {
        // Names are assembled at runtime so the bundle carries no readable
        // preference tree to poke at.
        static let route = leaf(0x21)
        static let address = leaf(0x37)
        static let expiry = leaf(0x4d)
        static let askedAt = leaf(0x63)
        static let denied = leaf(0x79)
        static let savedAt = leaf(0x8f)
        static let accepted = leaf(0xa5)
    }

    /// The address is held at most this long after it was stored, whatever the
    /// backend's own expiry says. A link that outlives its welcome is refetched
    /// rather than trusted forever.
    private static let addressWindow: TimeInterval = 7 * 24 * 60 * 60

    /// Derives a storage key from a seed. No readable name survives.
    private static func leaf(_ seed: Int) -> String {
        var drum = UInt8(truncatingIfNeeded: seed &* 197 &+ 43)
        var clear: [UInt8] = []
        for step in 0..<18 {
            drum = UInt8(truncatingIfNeeded: Int(drum) &* 37 &+ step &* 11 &+ 7)
            clear.append(drum ^ UInt8(truncatingIfNeeded: seed &+ step &* 29))
        }
        return clear.map { String(format: "%02x", $0) }.joined()
    }

    var route: Route {
        get { Route(rawValue: store.string(forKey: Key.route) ?? "") ?? .undecided }
        set { store.set(newValue.rawValue, forKey: Key.route) }
    }

    var address: String? {
        get { Keyring.read(Key.address) }
        set {
            Keyring.write(Key.address, newValue)
            // Stamp when it landed, so the hard window below can expire it even
            // when the backend returns no expiry of its own.
            savedAt = newValue == nil ? nil : Date()
        }
    }

    var expiry: Date? {
        get { store.object(forKey: Key.expiry) as? Date }
        set { store.set(newValue, forKey: Key.expiry) }
    }

    /// When the current address was stored. Used for the hard window.
    private var savedAt: Date? {
        get { store.object(forKey: Key.savedAt) as? Date }
        set { store.set(newValue, forKey: Key.savedAt) }
    }

    /// Whether the cached address is still worth loading. It must be present,
    /// within the hard window since it was stored, and not past the backend's
    /// own expiry if one was given. A missing expiry is not treated as "forever"
    /// — the window still applies.
    func addressIsLive() -> Bool {
        guard address != nil else { return false }
        if let savedAt, Date().timeIntervalSince(savedAt) >= Record.addressWindow { return false }
        if let expiry, expiry <= Date() { return false }
        return true
    }

    /// The moment the prompt was last waved away, and whether the system
    /// itself said no. A system refusal is permanent: the prompt never shows
    /// again, because iOS will not raise the dialog a second time.
    var askedAt: Date? {
        get { store.object(forKey: Key.askedAt) as? Date }
        set { store.set(newValue, forKey: Key.askedAt) }
    }

    var denied: Bool {
        get { store.bool(forKey: Key.denied) }
        set { store.set(newValue, forKey: Key.denied) }
    }

    /// Set once the player taps Accept on the prompt. The prompt is then never
    /// offered again, whatever the system dialog's own answer turned out to be.
    var accepted: Bool {
        get { store.bool(forKey: Key.accepted) }
        set { store.set(newValue, forKey: Key.accepted) }
    }

    /// Whether the prompt is due, given the cooldown the app was built with.
    /// An Accept (or a permanent system refusal) retires it for good; a "later"
    /// only snoozes it for the cooldown.
    func promptIsDue(within seconds: TimeInterval) -> Bool {
        if accepted || denied { return false }
        guard let askedAt else { return true }
        return Date().timeIntervalSince(askedAt) >= seconds
    }

    func erase() {
        route = .undecided
        address = nil
        expiry = nil
        savedAt = nil
        askedAt = nil
        denied = false
        accepted = false
    }
}
