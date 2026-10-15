import UIKit

/// Application entry. No storyboard: the window is built in code so the first
/// frame is ours. The scene delegate below is what the current SDK insists on.
@main
final class Pylon: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        true
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
        Deck.shared.liftBed()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        Oracle.shared.preserve(force: true)
    }
}
