import UIKit
import WebKit

/// The privacy policy and the support page, shown inside the game. These are
/// the only two addresses the app ever loads, and nothing else in the game
/// needs a connection: if the page fails, the player is told exactly that.
final class WebStage: Stage, WKNavigationDelegate {
    override var titleLexeme: UInt16? { heading }
    override var sceneWish: Int? { nil }
    override var wantsPurse: Bool { false }

    private let heading: UInt16
    private let address: UInt16
    private var pane: WKWebView!
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let excuse = Slab(.warn)
    private let excuseTitle = chisel("", Scribe.carved(16, .bold), Hide.parchment, lines: 2, align: .center)
    private let excuseBlurb = chisel("", Scribe.plain(12), Hide.murmur, lines: 0, align: .center)
    private let again = PressPad(.stone)

    init(_ heading: UInt16, _ address: UInt16) {
        self.heading = heading
        self.address = address
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func assemble() {
        let plan = WKWebViewConfiguration()
        plan.allowsInlineMediaPlayback = true
        pane = WKWebView(frame: .zero, configuration: plan)
        pane.navigationDelegate = self
        pane.isOpaque = false
        pane.backgroundColor = .clear
        pane.scrollView.backgroundColor = Hide.pitch
        pane.scrollView.indicatorStyle = .white
        pane.layer.cornerRadius = Grid.corner
        pane.layer.cornerCurve = .continuous
        pane.clipsToBounds = true
        pane.pin(into: canvas, inset: Grid.gutter)

        spinner.color = Hide.gild
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(spinner)

        excuseTitle.text = Vault.say(Lexeme.webFailTitle)
        excuseBlurb.text = Vault.say(Lexeme.webFailBlurb)
        again.dress(Vault.say(Lexeme.webRetry))
        again.onPress = { [weak self] in self?.fetch() }
        let column = UIStackView(arrangedSubviews: [excuseTitle, excuseBlurb, again])
        column.axis = .vertical
        column.spacing = Grid.gap
        column.setCustomSpacing(Grid.inset, after: excuseBlurb)
        column.translatesAutoresizingMaskIntoConstraints = false
        excuse.addSubview(column)
        excuse.alpha = 0
        excuse.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(excuse)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
            excuse.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            excuse.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
            excuse.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: Grid.gutter * 2),
            excuse.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -Grid.gutter * 2),
            column.topAnchor.constraint(equalTo: excuse.topAnchor, constant: Grid.inset),
            column.leadingAnchor.constraint(equalTo: excuse.leadingAnchor, constant: Grid.inset),
            column.trailingAnchor.constraint(equalTo: excuse.trailingAnchor, constant: -Grid.inset),
            column.bottomAnchor.constraint(equalTo: excuse.bottomAnchor, constant: -Grid.inset),
            again.heightAnchor.constraint(equalToConstant: Grid.touch),
        ])

        fetch()
    }

    private func fetch() {
        guard let spot = URL(string: Vault.say(address)) else {
            stumble()
            return
        }
        UIView.animate(withDuration: 0.2) { self.excuse.alpha = 0 }
        spinner.startAnimating()
        pane.load(URLRequest(url: spot, timeoutInterval: 20))
    }

    private func stumble() {
        spinner.stopAnimating()
        UIView.animate(withDuration: 0.24) { self.excuse.alpha = 1 }
    }

    func webView(_ pane: WKWebView, didFinish navigation: WKNavigation!) {
        spinner.stopAnimating()
    }

    func webView(_ pane: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        stumble()
    }

    func webView(
        _ pane: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        stumble()
    }
}
