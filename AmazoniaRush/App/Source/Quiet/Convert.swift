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

    /// The moment the ATT prompt stopped standing between the launch and its
    /// answer. `nil` means it is still unresolved — the prompt is on screen
    /// awaiting the player's choice — and the attribution wait pauses until it
    /// is set. It is stamped the instant the status is already known (no prompt
    /// on this launch) or the instant the player makes their choice, and the
    /// bounded install window only begins counting from it, so a player taking
    /// their time to read the prompt is never timed out into an organic result.
    private var attResolvedAt: Date?
    private var trackingAsked = false

    private let store = UserDefaults.standard
    /// Storage key for the frozen attribution. A derived, non-descriptive name,
    /// in keeping with the rest of the quiet side's bookkeeping.
    private static let frozenKey = "cv.9f3a1c7e4b2d"

    private override init() { super.init() }

    /// The attribution frozen on the first launch that produced a decisive
    /// (non-organic) answer. Once set, it is the authoritative attribution for
    /// every later config request, so the body a returning launch posts is the
    /// same one the first launch posted — `af_status` can never slip from
    /// non-organic to organic between requests (which the backend would read as
    /// organic and answer with no URL, dropping a paid install into the game).
    /// It is never overwritten by a later organic answer; an install only
    /// attributed on a later launch still freezes the first non-organic answer
    /// it sees, which is what lets a game-routed user recover to the web side.
    private var frozenConversion: [String: Any]? {
        get {
            guard let data = store.data(forKey: Convert.frozenKey),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return dict
        }
        set {
            guard let newValue, JSONSerialization.isValidJSONObject(newValue),
                  let data = try? JSONSerialization.data(withJSONObject: newValue) else {
                store.removeObject(forKey: Convert.frozenKey)
                return
            }
            store.set(data, forKey: Convert.frozenKey)
        }
    }

    /// Whether an attribution answer is decisive — present and not organic.
    /// Only a decisive answer is worth freezing; an organic or empty one is
    /// left open so a later launch can still be attributed.
    private func isDecisive(_ dict: [String: Any]) -> Bool {
        guard let status = (dict["af_status"] as? String)?.lowercased() else { return false }
        return status != "organic"
    }

    /// Starts the SDK and waits a bounded time for the install answer. A
    /// failure never hangs the boot: the gate is told there is no answer and
    /// proceeds, which is what keeps an offline install alive.
    func begin(
        within span: TimeInterval,
        onProgress: ((Float) -> Void)? = nil,
        then: @escaping (Bool) -> Void
    ) {
        lock.lock(); defer { lock.unlock() }
        guard !settled else { onProgress?(1); then(true); return }

        let key = Cap.attributionKey
        guard !key.isEmpty, !key.hasPrefix("PLACEHOLDER") else {
            // No key yet: report honestly rather than pretending.
            settled = true
            onProgress?(1)
            then(false)
            return
        }

        #if canImport(AppsFlyerLib)
        AppsFlyerLib.shared().appsFlyerDevKey = key
        AppsFlyerLib.shared().appleAppID = Cap.store
        AppsFlyerLib.shared().isDebug = false
        AppsFlyerLib.shared().delegate = self
        // The SDK holds the install event back until the tracking answer is in,
        // so a granted IDFA is attached to attribution rather than arriving a
        // beat too late. The ceiling is generous because the player is given as
        // long as they like to read the prompt; the matching wait on this side
        // (below) keeps the boot itself paused for exactly that long. The prompt
        // is raised below, after the first frame is up.
        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 54)
        #if DEBUG
        AppsFlyerLib.shared().isDebug = true
        #endif
        AppsFlyerLib.shared().start()
        requestTracking()
        // The SDK's identifier for this install; the config body and the
        // organic re-query both key off it.
        uid = AppsFlyerLib.shared().getAppsFlyerUID()

        // The conversion answer arrives on its own schedule. Wait for it, but
        // never longer than the caller allows — and never start that countdown
        // while the ATT prompt is still on screen. A player reading the prompt
        // is given all the time they need; the window, and with it the bar's
        // climb through this stage, only begins once they have made their
        // choice. The elapsed share of the window is then reported as it ticks,
        // so the boot bar hooks onto this wait — the single longest stage of
        // the launch — and climbs smoothly instead of freezing until the
        // answer lands.
        func peek() {
            guard let clearedAt = self.attResolvedAt else {
                // ATT still unresolved: hold the bar at this stage's start and
                // keep waiting for the player, without touching the deadline.
                onProgress?(0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: peek)
                return
            }
            let deadline = clearedAt.addingTimeInterval(span)
            if self.settled || Date() >= deadline {
                self.settled = true
                onProgress?(1)
                then(self.settled)
                return
            }
            let elapsed = Date().timeIntervalSince(clearedAt)
            onProgress?(Float(min(1, max(0, elapsed / span))))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: peek)
        }
        peek()
        #else
        settled = true
        onProgress?(1)
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

        // 1. Install attribution, verbatim. The frozen first-launch answer is
        //    preferred when one exists, so the body does not change its
        //    af_status between requests; otherwise whatever this launch
        //    produced is used (and may itself be frozen below, in `adopt`).
        let attribution = frozenConversion ?? conversion
        for (key, value) in attribution { body[key] = value }

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
        // Freeze the first decisive attribution so every later config request
        // repeats it verbatim. A non-organic status, once seen, is never given
        // up: a later launch's fresh (often organic, by SDK timing) answer can
        // no longer flip the body and drop a paid install into the game.
        if frozenConversion == nil, isDecisive(fresh) {
            frozenConversion = fresh
        }
        lock.unlock()
    }

    /// Raises the tracking prompt once per process. Called right after the SDK
    /// starts, which is after the first frame is on screen — iOS silently drops
    /// the request before the app is active, so the small delay guards against a
    /// prompt fired mid-transition being lost. Only asked while the status is
    /// still undetermined, so a decided user is never pestered again.
    ///
    /// Crucially, it records when the prompt is resolved: `attResolvedAt` is
    /// left `nil` while the prompt is on screen and stamped the moment the
    /// player makes a choice, which is what releases the paused install wait.
    /// A status that is already decided (a returning launch) resolves it at
    /// once, so such a launch never pauses.
    private func requestTracking() {
        guard !trackingAsked else { return }
        trackingAsked = true
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
            // Already answered on an earlier launch: nothing to wait for.
            attResolvedAt = Date()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else {
                // Resolved in the meantime, or the prompt could not be shown
                // this launch: do not hold the boot waiting on it.
                self.attResolvedAt = Date()
                return
            }
            ATTrackingManager.requestTrackingAuthorization { _ in
                // The player has chosen and the prompt is gone: release the
                // wait so the launch resumes from here.
                DispatchQueue.main.async { self.attResolvedAt = Date() }
            }
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
