import Foundation

/// The organic false positive.
///
/// The attribution SDK sometimes reports "Organic" on the very first run
/// even for a paid install, because it answered before the network reply
/// landed. The fix is to ask again shortly afterwards and prefer that
/// answer, so a paying visitor is not filed as organic on launch one.
enum Gcd {
    /// The wait before re-asking. Long enough for a first fetch to land,
    /// short enough that the player does not notice.
    private static let pause: TimeInterval = 7

    /// Runs `then` with the corrected conversion data. The original answer
    /// is returned untouched when it was not organic, when no identifier is
    /// known, or when the re-query fails.
    static func settle(_ original: [String: Any], uid: String?, then: @escaping ([String: Any]) -> Void) {
        let status = original["af_status"] as? String
        // Re-query in two cases:
        //   - the SDK labelled this install "Organic" (it often does so before
        //     the network reply lands, filing paid installs as organic), or
        //   - no answer arrived in the boot window at all (empty data): on a
        //     slow cold launch the conversion callback can fire well after the
        //     window's ceiling, and posting an empty body is read as organic
        //     just the same.
        // A present, non-organic status is trusted and sent straight through.
        guard status == "Organic" || status == nil,
              let uid, !uid.isEmpty,
              !Cap.attributionKey.isEmpty else {
            then(original)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + pause) {
            query(uid) { fresh in
                guard let fresh, !fresh.isEmpty else { then(original); return }
                var merged = original
                for (key, value) in fresh { merged[key] = value }
                // The identifier from the fresh answer wins when there is one.
                then(merged)
            }
        }
    }

    /// One look-up against the SDK's own install-data endpoint. On iOS the key
    /// is the numeric App Store id (`id<storeId>`) on the v5 path, not the
    /// bundle id — the bundle id returns empty data here and the correction
    /// silently never happens, filing paid installs as organic.
    private static func query(_ uid: String, then: @escaping ([String: Any]?) -> Void) {
        let store = Cap.store
        guard !store.isEmpty,
              let base = URL(string: "https://gcdsdk.appsflyer.com/install_data/v5.0/id\(store)") else {
            then(nil)
            return
        }
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false)
        parts?.queryItems = [URLQueryItem(name: "device_id", value: uid)]
        guard let address = parts?.url else { then(nil); return }

        var request = URLRequest(url: address)
        request.timeoutInterval = 12
        request.setValue("Bearer " + Cap.attributionKey, forHTTPHeaderField: "Authorization")
        request.setValue(Signal.userAgent, forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            let parsed = data.flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            }
            DispatchQueue.main.async { then(parsed) }
        }.resume()
    }
}
