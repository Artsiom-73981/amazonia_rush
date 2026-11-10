import Foundation

/// Holds the APNs token and the messaging sender id for as long as the app
/// runs. The token arrives on its own schedule, often after the first config
/// request has already gone out, so it is kept here and folded into the body
/// of whatever request happens next.
///
/// When there is no token the field is left out of the body entirely. It is
/// never sent as an empty string or a null, which the contract forbids.
final class Holder {
    static let shared = Holder()

    private let lock = NSLock()
    private var apns: String?
    private var watchers: [(String) -> Void] = []

    private init() {}

    /// Records a token, or the fact that there is none. Reaching the endpoint
    /// again as soon as a token lands is what keeps the backend's view fresh.
    func note(token: String?) {
        lock.lock()
        let changed = apns != token
        apns = token
        let waiting = watchers
        watchers.removeAll()
        lock.unlock()
        guard changed, let token else { return }
        DispatchQueue.main.async { waiting.forEach { $0(token) } }
    }

    var token: String? {
        lock.lock(); defer { lock.unlock() }
        return apns
    }

    /// Runs `then` as soon as a token exists, immediately if one already does.
    func whenToken(_ then: @escaping (String) -> Void) {
        lock.lock()
        if let apns {
            lock.unlock()
            DispatchQueue.main.async { then(apns) }
            return
        }
        watchers.append(then)
        lock.unlock()
    }

    /// The two fields the contract adds to the config body when a token is
    /// ready. An absent token yields no keys at all.
    func pushFields() -> [String: Any] {
        guard let apns, !apns.isEmpty else { return [:] }
        let sender = Cap.sender
        var fields: [String: Any] = ["push_token": apns]
        if !sender.isEmpty { fields["firebase_project_id"] = sender }
        return fields
    }
}
