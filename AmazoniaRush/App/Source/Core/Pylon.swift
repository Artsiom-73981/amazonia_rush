import UIKit
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Application entry. No storyboard: the window is built in code so the first
/// frame is ours. The scene delegate below is what the current SDK insists on.
@main
final class Pylon: UIResponder, UIApplicationDelegate {
    /// Runs before `didFinishLaunching`. The notification delegate is claimed
    /// here, at the earliest hook there is: for the exact tap that cold-starts
    /// the app from killed, registering the delegate only in `didFinishLaunching`
    /// can already be too late for iOS to reliably route that tap into
    /// `Courier.didReceive(response:)`. Claiming it here is what makes the
    /// cold-start tap land every time rather than once in a while.
    func application(
        _ application: UIApplication,
        willFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().delegate = Courier.shared
        #endif
        return true
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Only a genuine tap on a notification routes to the quiet side. The
        // cold-start tap is delivered through the scene's connection options
        // (see `Vestibule`) and, as a second reliable source, through
        // `Courier.didReceive`; both stash it for the boot decision to read
        // first. The legacy launch-options payload also fires for silent
        // pushes, which are not taps, so it is deliberately not read here.
        //
        // The core has to be awake before any sealed slot can be opened, and
        // the boot screen normally does that a moment from now. Wake it here
        // instead: messaging reads its identity as soon as it is touched, and
        // configuring it later leaves it unconfigured for the whole launch.
        Oracle.shared.awaken()
        Vault_service()
        return true
    }

    /// Wakes the core and raises Firebase from the sealed identity. Never from
    /// a plist: the bundle carries none, by design.
    private func Vault_service() {
        Ember.raise()
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// The APNs token, handed straight to the attribution layer so the config
    /// body carries it. A token that has not arrived yet is simply absent from
    /// the body rather than being sent as an empty string.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Ember.note(apns: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Holder.shared.note(token: nil)
    }

    /// A notification tapped while the app was running. One-shot, like the
    /// cold-start case: the destination is opened and then forgotten.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // A silent/background delivery is not a tap, so it never changes what
        // is on screen. Only a tap (handled in `Courier`) routes to the quiet
        // side.
        completionHandler(.newData)
    }

    /// Hands every window scene to `Vestibule`. Naming the delegate here rather
    /// than in the plist keeps the class name out of the bundle.
    func application(
        _ application: UIApplication,
        configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let plan = UISceneConfiguration(name: nil, sessionRole: session.role)
        plan.delegateClass = Vestibule.self
        return plan
    }

    func applicationWillTerminate(_ application: UIApplication) {
        Oracle.shared.preserve(force: true)
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        Vault.releaseScenery()
    }
}

/// The window scene: raises the loading screen, then carries the save and the
/// audio bed through every trip in and out of the foreground.
final class Vestibule: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) {
        guard let stage = scene as? UIWindowScene else { return }
        // A cold-start tap on a notification arrives here, with the response in
        // the connection options. It is stashed before the first frame so the
        // boot decision reads it first and the pushed link wins over the config
        // route. Only a tap is honoured — nothing else is read.
        if let remote = options.notificationResponse?.notification.request.content.userInfo as? [AnyHashable: Any],
           let deep = Tap.deepLink(in: remote) {
            Tap.stash(deep)
        }
        let frame = UIWindow(windowScene: stage)
        frame.backgroundColor = Hide.pitch
        frame.rootViewController = Director.shared
        window = frame
        frame.makeKeyAndVisible()
        Director.shared.raise(BootStage())
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        Oracle.shared.preserve(force: true)
        Deck.shared.dropBed()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        guard Director.shared.crown != nil else { return }
        _ = Oracle.shared.heartbeat()
        Oracle.shared.preserve()
        Director.shared.crown?.awaken()
        // Resume the bed only if the screen on top is the native game; on the
        // loading screen or the quiet side this stays silent.
        Director.shared.syncAudio()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        Oracle.shared.preserve(force: true)
    }

}
