import Foundation
#if canImport(FirebaseCore)
import FirebaseCore
import FirebaseMessaging
#endif

/// Raises Firebase from the sealed identity instead of a bundled plist.
///
/// Every value the options need is opened from the oracle at launch, so the
/// app carries no readable inventory of its own backend. If the core is not
/// awake or the fields are missing, this reports failure and the app runs
/// without messaging rather than crashing.
enum Ember {
    private static var raised = false

    /// Configures the default app. Safe to call more than once.
    @discardableResult
    static func raise() -> Bool {
        guard !raised else { return true }
        #if canImport(FirebaseCore)
        guard Props.ready else { return false }
        let fields = Props.fields
        let options = FirebaseOptions(googleAppID: fields.appId, gcmSenderID: fields.sender)
        options.apiKey = fields.key
        options.projectID = fields.project
        options.storageBucket = fields.bucket
        options.bundleID = Cap.bundle
        FirebaseApp.configure(options: options)
        raised = true
        // The token is handed to the same holder the config body reads from.
        Messaging.messaging().token { token, _ in Holder.shared.note(token: token) }
        Messaging.messaging().delegate = Courier.shared
        return true
        #else
        return false
        #endif
    }

    /// The APNs token, forwarded so messaging can mate it with its own.
    static func note(apns token: Data) {
        #if canImport(FirebaseMessaging)
        Messaging.messaging().apnsToken = token
        #endif
    }
}

#if canImport(FirebaseMessaging)
import UserNotifications

/// Keeps the token fresh and shows a foreground notification as a banner.
final class Courier: NSObject, MessagingDelegate, UNUserNotificationCenterDelegate {
    static let shared = Courier()

    /// A rotated token is folded into the next config request rather than
    /// starting one of its own.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Holder.shared.note(token: fcmToken)
        if let fcmToken { Hearth.shared.tokenArrived(fcmToken) }
    }

    /// In the foreground the system banner is used, so the player never sees
    /// the same message twice.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// A notification tapped while the app was backgrounded (not killed) is
    /// delivered here rather than through the launch options. The address is
    /// opened straight away if a screen is already up, and stashed for the boot
    /// path to consume first if the app is still coming up.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let deep = Tap.deepLink(in: info) {
            if let crown = Director.shared.crown, !(crown is BootStage) {
                // A real screen is already up (warm tap): open the link now,
                // and do not leave a stash behind to hijack the next cold
                // launch — this launch has already consumed its own.
                _ = Tap.consume()
                Hearth.shared.openTapped(deep)
            } else {
                // Still booting, or no screen yet (cold tap): stash the link so
                // the boot decision reads it first and the pushed page wins
                // over the config route. This is the second reliable cold-start
                // source alongside the scene's connection options — whichever
                // fires, the one-shot store holds the same link for the boot
                // decision to consume exactly once.
                Tap.stash(deep)
            }
        }
        completionHandler()
    }
}
#endif
