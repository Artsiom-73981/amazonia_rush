import UIKit
import WebKit

/// The quiet side: the destination the backend named, drawn full-screen. This
/// is the only place in the app that loads an address it was told about.
///
/// It is a Stage like any other so the app has one screen model, but it hides
/// the dock and the purse: nothing about the game shows through.
///
/// The safe area is handled natively: the web view's frame is pinned to the
/// safe-area guide and the space around it is painted black, so the page is
/// always inset from the notch and the home indicator on every edge, in both
/// orientations. No JavaScript measures or injects the inset — a frame the OS
/// lays out cannot "slip" the way a CSS variable rewritten after load can.
final class ScreenStage: Stage, WKNavigationDelegate, WKUIDelegate {
    override var orientationWish: UIInterfaceOrientationMask { .allButUpsideDown }
    override var wantsPurse: Bool { false }
    override var hidesDock: Bool { true }
    override var playsAudio: Bool { false }

    private let address: String
    private var pane: WKWebView!
    // The web view is pinned to the view's edges with constant insets kept in
    // step with the device's real safe area, rather than to the safe-area
    // guide, whose top collapses once the status bar is hidden.
    private var paneTop: NSLayoutConstraint!
    private var paneLeading: NSLayoutConstraint!
    private var paneTrailing: NSLayoutConstraint!
    private var paneBottom: NSLayoutConstraint!
    private let backfill = UIView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let wash = UIView()

    /// Navigations are gated by scheme only. There is deliberately no host
    /// allowlist: the backend may move the partner host after release, and an
    /// allowlist would silently drop the new one.
    private static let web: Set<String> = ["http", "https", "about", "data", "blob"]

    /// A redirect loop is retried from the last address it reached a few times
    /// before the player is told, rather than being shown a blank error page.
    private var redirectTries = 0
    private let redirectLimit = 4
    /// The deepest main-frame address the chain has reached. A "too many
    /// redirects" failure is retried from here, which resets WKWebView's own
    /// per-navigation redirect counter and lets an affiliate chain finish.
    private var lastMainFrame: String?

    init(address: String) {
        self.address = address
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func assemble() {
        view.backgroundColor = Hide.pitch

        // Black fills the whole screen; the page is laid on top of it inside
        // the safe area, so the notch and home-indicator margins read as a
        // clean black border rather than showing the game's backdrop through.
        backfill.backgroundColor = Hide.pitch
        backfill.pin(into: view)

        let plan = WKWebViewConfiguration()
        plan.allowsInlineMediaPlayback = true
        plan.mediaTypesRequiringUserActionForPlayback = []
        plan.preferences.javaScriptCanOpenWindowsAutomatically = true
        // The quiet side keeps its own session, so nothing it stores can be
        // read back by the game or the other way round.
        plan.websiteDataStore = .default()
        // One self-contained bundle, injected into every frame on every
        // navigation (not evaluated once from `didFinish`). It locks the
        // viewport to the device width, kills pinch/double-tap zoom and holds
        // the text size steady, so a rotation never reads as the page being
        // zoomed in — and because it re-runs on each document it cannot be
        // undone by the site's own later navigations.
        let guardScript = WKUserScript(
            source: Self.bundledScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        plan.userContentController.addUserScript(guardScript)

        pane = WKWebView(frame: .zero, configuration: plan)
        pane.navigationDelegate = self
        pane.uiDelegate = self
        pane.allowsBackForwardNavigationGestures = true
        pane.scrollView.contentInsetAdjustmentBehavior = .never
        // The page is not a document to pinch around: lock the zoom at the
        // scroll view too, so nothing can scale it even if a stray gesture or a
        // rotation tries to.
        pane.scrollView.minimumZoomScale = 1
        pane.scrollView.maximumZoomScale = 1
        pane.scrollView.bouncesZoom = false
        pane.isOpaque = false
        pane.backgroundColor = Hide.pitch
        pane.scrollView.backgroundColor = Hide.pitch
        pane.customUserAgent = Signal.userAgent
        pane.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pane)
        paneTop = pane.topAnchor.constraint(equalTo: view.topAnchor)
        paneLeading = pane.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        paneTrailing = pane.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        paneBottom = pane.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([paneTop, paneLeading, paneTrailing, paneBottom])
        applySafeInsets()

        wash.backgroundColor = Hide.pitch
        wash.pin(into: view)
        spinner.color = Hide.gild
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        wash.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: wash.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: wash.centerYAnchor),
        ])

        load(address)
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.applySafeInsets()
        }, completion: { [weak self] _ in
            self?.reflow()
        })
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        applySafeInsets()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applySafeInsets()
    }

    /// Keeps the web view inside the device's real safe area, in every
    /// orientation. The controller's own `safeAreaInsets` cannot be trusted:
    /// with the status bar hidden its top inset collapses well below the notch
    /// (e.g. 23pt instead of the device's 62pt), which let the page slip up
    /// under the sensor housing. The window's insets are the physical ones and
    /// never collapse, so the per-edge maximum of the two is always the true
    /// safe area — the same inset the page sits in whatever the launch did.
    private func applySafeInsets() {
        guard paneTop != nil else { return }
        let own = view.safeAreaInsets
        let device = view.window?.safeAreaInsets ?? own
        let top = max(own.top, device.top)
        let left = max(own.left, device.left)
        let right = max(own.right, device.right)
        let bottom = max(own.bottom, device.bottom)
        guard paneTop.constant != top
            || paneLeading.constant != left
            || paneTrailing.constant != -right
            || paneBottom.constant != -bottom
        else { return }
        paneTop.constant = top
        paneLeading.constant = left
        paneTrailing.constant = -right
        paneBottom.constant = -bottom
    }

    private func load(_ link: String) {
        guard let target = URL(string: link) else { return }
        lastMainFrame = link
        spinner.startAnimating()
        wash.isHidden = false
        pane.load(URLRequest(url: target))
    }

    // --- navigation -------------------------------------------------------

    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let target = action.request.url, let scheme = target.scheme?.lowercased() else {
            decisionHandler(.cancel)
            return
        }
        // Anything that is not a web document scheme is a deep link: hand it
        // straight to the system, which routes it to whatever app owns it
        // (the store, a messenger, a bank app, a custom partner scheme). The
        // page stays put. This is what lets the quiet side open other apps.
        guard Self.web.contains(scheme) else {
            UIApplication.shared.open(target)
            decisionHandler(.cancel)
            return
        }
        // Remember the furthest main-frame address, so a redirect-loop failure
        // can be retried from where the chain actually stopped.
        if action.targetFrame?.isMainFrame ?? true {
            lastMainFrame = target.absoluteString
        }
        decisionHandler(.allow)
    }

    /// Server-side (3xx) redirects do not come back through the policy handler,
    /// so the furthest address is also tracked here.
    func webView(
        _ webView: WKWebView,
        didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!
    ) {
        if let here = webView.url?.absoluteString, !here.isEmpty {
            lastMainFrame = here
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        redirectTries = 0
        spinner.stopAnimating()
        wash.isHidden = true
        // Some sites finish their layout a beat after load; a single resize
        // nudge lets a late-built header settle to the locked viewport.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.pane.evaluateJavaScript(
                "window.dispatchEvent(new Event('resize'));"
                + "if(window.visualViewport){window.visualViewport.dispatchEvent(new Event('resize'));}"
            )
        }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        // A cancelled load is what a redirect looks like from here, and is
        // never a reason to show the player anything.
        let ns = error as NSError
        if ns.code == NSURLErrorCancelled { return }
        if ns.code == NSURLErrorHTTPTooManyRedirects, redirectTries < redirectLimit {
            redirectTries += 1
            // Reload the address that actually hit the limit (or the furthest
            // one reached) in a fresh navigation. That resets WKWebView's
            // per-load redirect counter, so an affiliate chain that is longer
            // than the built-in limit still lands on its destination instead of
            // a blank "too many redirects" page.
            let failing = (ns.userInfo[NSURLErrorFailingURLStringErrorKey] as? String)
                ?? lastMainFrame
                ?? webView.url?.absoluteString
                ?? address
            load(failing)
            return
        }
        fail()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        fail()
    }

    private func fail() {
        spinner.stopAnimating()
        // The address could not be reached. If the connection is genuinely
        // gone the player gets the honest screen; otherwise they are told the
        // page itself failed.
        if !Gauge.shared.live {
            Director.shared.homeward()
            let stalled = DeadEndStage()
            stalled.onRetry = { [weak self] in
                Director.shared.back()
                if let link = self?.address { self?.load(link) }
            }
            Director.shared.go(stalled)
        } else {
            wash.isHidden = false
            whisper(Vault.say(Lexeme.webFailTitle), sour: true)
        }
    }

    /// After a rotation WKWebView holds the pre-rotation viewport width for a
    /// moment, which reads as the page being zoomed in. The injected guard has
    /// already locked the scale; nudging the page to reflow a few times as the
    /// native frame settles snaps it back cleanly.
    private func reflow() {
        let beats: [Double] = [0.05, 0.2, 0.45, 0.75]
        for delay in beats {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.pane.evaluateJavaScript(
                    "window.dispatchEvent(new Event('orientationchange'));"
                    + "window.dispatchEvent(new Event('resize'));"
                    + "if(window.visualViewport){window.visualViewport.dispatchEvent(new Event('resize'));}"
                )
            }
        }
    }

    // --- windows ----------------------------------------------------------

    /// A `target="_blank"` link or a `window.open` call. A web address is
    /// loaded in place rather than dropped; a deep-link scheme is handed to
    /// the system so the owning app opens.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let target = navigationAction.request.url else { return nil }
        let scheme = target.scheme?.lowercased() ?? ""
        if Self.web.contains(scheme) {
            webView.load(navigationAction.request)
        } else {
            UIApplication.shared.open(target)
        }
        return nil
    }

    /// File inputs open the system chooser without any app-wide permission.
    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }

    // --- injected guard ----------------------------------------------------

    /// One merged behaviour bundle, injected into every frame at document end.
    /// Locks the viewport to the device width, suppresses pinch / double-tap
    /// zoom and holds the text size and input font steady so a rotation never
    /// looks like a pinch-zoom and no focused field triggers an auto-zoom.
    private static let bundledScript = """
    (function(){
      if (window.__amzReady) { return; }
      window.__amzReady = true;

      var content = 'width=device-width,initial-scale=1,maximum-scale=1,minimum-scale=1,user-scalable=no,viewport-fit=cover';
      var meta = document.querySelector('meta[name="viewport"]');
      if (meta) { meta.setAttribute('content', content); }
      else {
        meta = document.createElement('meta');
        meta.name = 'viewport'; meta.content = content;
        (document.head || document.documentElement).appendChild(meta);
      }

      document.addEventListener('gesturestart', function(e){ e.preventDefault(); }, {passive:false});
      document.addEventListener('gesturechange', function(e){ e.preventDefault(); }, {passive:false});
      var lastTap = 0;
      document.addEventListener('touchend', function(e){
        var now = Date.now();
        if (now - lastTap <= 300) { e.preventDefault(); }
        lastTap = now;
      }, {passive:false});

      var style = document.createElement('style');
      style.textContent =
        '*{-webkit-tap-highlight-color:transparent!important;}' +
        'html,body{overscroll-behavior:none!important;overscroll-behavior-y:none!important;}' +
        'html{-webkit-text-size-adjust:100%!important;text-size-adjust:100%!important;}' +
        'input,textarea,select,[contenteditable="true"]{font-size:max(16px,1em)!important;}' +
        '::-webkit-scrollbar{width:6px;height:6px;}' +
        '::-webkit-scrollbar-thumb{background:#8a6a2e99;border-radius:3px;}';
      (document.head || document.documentElement).appendChild(style);
    })();
    """
}
