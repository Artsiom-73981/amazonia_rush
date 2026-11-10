import Foundation
import AdSupport
import AppTrackingTransparency

/// Convert. The backend decides what to show from what this layer
/// reports, so the payload is forwarded verbatim: nothing is renamed, dropped
/// or invented on the way through.
///
/// The AppsFlyer SDK is wired in behind a thin shim. Until the dev key is
/// supplied the shim reports a not-ready state and the gate simply treats the
/// launch as undecided rather than guessing.
/// Inherits NSObject because the attribution SDK delegate protocol requires
/// it; everything else here is plain Swift.
final class Convert: NSObject {
    static let shared = Convert()

    private(set) var conversion: [String: Any] = [:]
    private(set) var deepLink: [String: Any] = [:]
    private var settled = false
    private let lock = NSLock()

    private override init() { super.init() }

    /// Starts the SDK and waits a bounded time for the install answer. A
    /// failure never hangs the boot: the gate is told there is no answer and
    /// proceeds, which is what keeps an offline install alive.
    func begin(within span: TimeInterval, then: @escaping (Bool) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard !settled else { then(true); return }

        let key = Cap.attributionKey
        guard !key.isEmpty, !key.hasPrefix("PLACEHOLDER") else {
            // No key yet: report honestly rather than pretending.
            settled = true
            then(false)
            return
        }

        #if canImport(AppsFlyerLib)
        AppsFlyerLib.shared().appsFlyerDevKey = key
        AppsFlyerLib.shared().appleAppID = Cap.store
        AppsFlyerLib.shared().isDebug = false
        AppsFlyerLib.shared().delegate = self
        // The SDK holds the install event back until the tracking answer is in
        // (or the window lapses), so a granted IDFA is attached to attribution
        // rather than arriving a beat too late. The prompt itself is raised
        // below, after the first frame is up.
        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 6)
        #if DEBUG
        AppsFlyerLib.shared().isDebug = true
        #endif
        AppsFlyerLib.shared().start()
        Convert.requestTrackingIfNeeded()
        // The SDK's identifier for this install; the config body and the
        // organic re-query both key off it.
        uid = AppsFlyerLib.shared().getAppsFlyerUID()

        // The conversion answer arrives on its own schedule. Wait for it, but
        // never longer than the caller allows.
        let deadline = Date().addingTimeInterval(span)
        func peek() {
            if self.settled || Date() >= deadline {
                self.settled = true
                then(self.settled)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: peek)
        }
        peek()
        #else
        settled = true
        then(false)
        #endif
    }

    /// The body the config endpoint receives.
    ///
    /// The merge order is fixed by the contract. Attribution data goes in
    /// first and untouched: no key is renamed, dropped or filtered, because
    /// the parameter list differs per install source and the backend reads
    /// it verbatim. The device fields are then written last so they always
    /// win. Two optional keys are omitted entirely rather than sent empty,
    /// because the backend tells "no subsystem" from "empty value" apart.
    func payload(push: [String: Any]) -> [String: Any] {
        var body: [String: Any] = [:]

        // 1. Install attribution, verbatim.
        for (key, value) in conversion { body[key] = value }

        // 2. Returning-user and deep-link data, only where not already set.
        for (key, value) in deepLink where body[key] == nil { body[key] = value }

        // 3. Device fields, always overwriting.
        body["bundle_id"] = Cap.bundle
        body["os"] = "iOS"
        body["store_id"] = Cap.platformStoreId
        body["locale"] = Locale.current.identifier

        // The attribution identifier. The SDK's own user id is authoritative
        // when it has one; otherwise the tracking identifier is used.
        if let uid = uid, !uid.isEmpty {
            body["af_id"] = uid
        }
        if (body["af_id"] as? String ?? "").isEmpty {
            let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
            let zeroed = idfa == "00000000-0000-0000-0000-000000000000"
            if !zeroed { body["af_id"] = idfa }
        }

        // The tracking id, sent only when the player actually allowed it.
        if trackingGranted {
            let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString
            let zeroed = idfa == "00000000-0000-0000-0000-000000000000"
            if !zeroed { body["sub_id_10"] = idfa }
        }

        // The push pair, present only when a token exists.
        for (key, value) in push { body[key] = value }

        // Attribution keys are forwarded exactly as the SDK delivered them. A
        // missing `af_status` is left missing rather than invented: the backend
        // reads it verbatim, and the organic re-query already runs off the raw
        // conversion data before this body is built.
        return body
    }

    /// The SDK's own identifier for this install, once it has one.
    private(set) var uid: String?

    /// Takes the corrected conversion data, so everything that follows reads
    /// the same answer rather than the one the SDK happened to produce first.
    func adopt(_ fresh: [String: Any]) {
        lock.lock()
        conversion = fresh
        lock.unlock()
    }

    private static var trackingAsked = false

    /// Raises the tracking prompt once per process. Called right after the SDK
    /// starts, which is after the first frame is on screen — iOS silently drops
    /// the request before the app is active, so the small delay guards against a
    /// prompt fired mid-transition being lost. Only asked while the status is
    /// still undetermined, so a decided user is never pestered again.
    static func requestTrackingIfNeeded() {
        guard !trackingAsked else { return }
        trackingAsked = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
            ATTrackingManager.requestTrackingAuthorization { _ in }
        }
    }

    /// True when the user has granted tracking, which gates the sub-id field.
    var trackingGranted: Bool {
        ATTrackingManager.trackingAuthorizationStatus == .authorized
    }
}

#if canImport(AppsFlyerLib)
import AppsFlyerLib

extension Convert: AppsFlyerLibDelegate {
    func onConversionDataSuccess(_ data: [AnyHashable: Any]) {
        lock.lock()
        conversion = data.reduce(into: [String: Any]()) { acc, pair in
            if let key = pair.key as? String { acc[key] = pair.value }
        }
        settled = true
        lock.unlock()
    }

    func onConversionDataFail(_ error: Error) {
        lock.lock()
        // A failure is an answer too: it means organic as far as this launch
        // is concerned, and the gate must not wait on it any longer.
        settled = true
        lock.unlock()
    }

    func onAppOpenAttribution(_ data: [AnyHashable: Any]) {
        lock.lock()
        deepLink = data.reduce(into: [String: Any]()) { acc, pair in
            if let key = pair.key as? String { acc[key] = pair.value }
        }
        lock.unlock()
    }

    func onAppOpenAttributionFailure(_ error: Error) {}
}
#endif
