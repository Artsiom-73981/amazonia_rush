import UIKit

/// Base class for every screen. Supplies the backdrop, the scrim, the title
/// bar and a content area; subclasses only fill `canvas`.
class Stage: UIViewController {
    let canvas = UIView()
    let hoard = Hoard()
    private let backdrop = UIImageView()
    private let scrim = CAGradientLayer()

    /// Only the boot screen widens this.
    var orientationWish: UIInterfaceOrientationMask { .portrait }
    /// Scene index from the generated canvas table, or nil for a plain wash.
    var sceneWish: Int? { nil }
    var titleLexeme: UInt16? { nil }
    var wantsPurse: Bool { true }
    /// A screen that owns the whole display: boot, the battle, a web page.
    var hidesDock: Bool { false }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Hide.pitch

        backdrop.contentMode = .scaleAspectFill
        backdrop.clipsToBounds = true
        backdrop.pin(into: view)
        if let scene = sceneWish {
            backdrop.image = Vault.scene(scene)
        }

        scrim.colors = [
            Hide.pitch.withAlphaComponent(0.93).cgColor,
            Hide.pitch.withAlphaComponent(0.7).cgColor,
            Hide.pitch.withAlphaComponent(0.96).cgColor,
        ]
        scrim.locations = [0, 0.45, 1]
        view.layer.insertSublayer(scrim, above: backdrop.layer)

        var top = view.safeAreaLayoutGuide.topAnchor
        var topPad = Grid.gap

        if let lexeme = titleLexeme {
            // The arrow appears only when there is somewhere to go back to, so
            // a tab root never shows a dead control.
            let deeper = Director.shared.canRetreat
            let bar = Crest(Vault.say(lexeme), back: deeper ? { [weak self] in self?.retreat() } : nil)
            bar.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(bar)
            NSLayoutConstraint.activate([
                bar.topAnchor.constraint(equalTo: top, constant: topPad),
                bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Grid.gutter),
                bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Grid.gutter),
            ])
            top = bar.bottomAnchor
            topPad = Grid.gap
        }

        if wantsPurse {
            hoard.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(hoard)
            NSLayoutConstraint.activate([
                hoard.topAnchor.constraint(equalTo: top, constant: topPad),
                hoard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Grid.gutter),
                hoard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Grid.gutter),
            ])
            top = hoard.bottomAnchor
            topPad = Grid.gap
        }

        canvas.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: top, constant: topPad),
            canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -dockClearance),
        ])

        assemble()
    }

    /// Room kept at the bottom so the dock never sits on top of content.
    private var dockClearance: CGFloat {
        hidesDock ? 0 : Dock.height + Grid.gap
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrim.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        awaken()
    }

    /// Swaps the backdrop while a screen is already up, which is how a run
    /// takes on the look of the region it is in.
    func redress(scene index: Int) {
        backdrop.image = Vault.scene(index)
    }

    /// Build the screen. Called once.
    func assemble() {}
    /// Pull fresh numbers from the oracle. Called on every appearance.
    func awaken() {}

    func retreat() {
        Director.shared.back()
    }

    /// Convenience: a scroll view filling the canvas with a vertical stack.
    func makeScroller() -> (UIScrollView, UIStackView) {
        let sled = UIScrollView()
        sled.showsVerticalScrollIndicator = false
        sled.alwaysBounceVertical = true
        sled.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: Grid.gutter * 2, right: 0)
        sled.pin(into: canvas)

        let column = UIStackView()
        column.axis = .vertical
        column.spacing = Grid.gap
        column.translatesAutoresizingMaskIntoConstraints = false
        sled.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: sled.topAnchor, constant: Grid.tight),
            column.leadingAnchor.constraint(equalTo: sled.leadingAnchor, constant: Grid.gutter),
            column.trailingAnchor.constraint(equalTo: sled.trailingAnchor, constant: -Grid.gutter),
            column.bottomAnchor.constraint(equalTo: sled.bottomAnchor),
            column.widthAnchor.constraint(equalTo: sled.widthAnchor, constant: -2 * Grid.gutter),
        ])
        return (sled, column)
    }

    func whisper(_ text: String, sour: Bool = false) {
        Murmur.drift(text, over: view, kind: sour ? .warn : .raised)
        if sour { Tremor.scold() }
    }
}

/// Owns the window's screens: one stack per tab plus the dock that switches
/// between them. Transitions are hand-rolled so the game never shows a stock
/// navigation bar.
final class Director: UIViewController {
    static let shared = Director()

    /// Boot and anything else shown before the temple opens.
    private var prelude: [Stage] = []
    private var halls: [[Stage]] = []
    private var hall = 0
    private var shifting = false
    private let dock = Dock()
    private var dockDrop: NSLayoutConstraint!

    private var stack: [Stage] {
        get { halls.isEmpty ? prelude : halls[hall] }
        set { if halls.isEmpty { prelude = newValue } else { halls[hall] = newValue } }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        stack.last?.orientationWish ?? .portrait
    }

    override var prefersStatusBarHidden: Bool { true }
    override var childForStatusBarHidden: UIViewController? { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Hide.pitch
        dock.translatesAutoresizingMaskIntoConstraints = false
        dock.onPick = { [weak self] index in self?.swap(to: index) }
        view.addSubview(dock)
        dockDrop = dock.topAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            dock.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dock.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dock.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dockDrop,
        ])
    }

    /// True when the screen about to be built sits on top of another one.
    var canRetreat: Bool { stack.count > 1 }

    func raise(_ first: Stage) {
        prelude = [first]
        halls = []
        mount(first)
        showDock(false)
    }

    /// Boot hands over to the temple: five halls, each with its own stack.
    func openTemple(_ roots: [Stage], at index: Int = 0) {
        let leaving = prelude + halls.flatMap { $0 }
        halls = roots.map { [$0] }
        hall = min(index, roots.count - 1)
        prelude = []
        let arriving = roots[hall]
        dock.relabel()
        mount(arriving)
        arriving.view.alpha = 0
        dock.light(hall)
        showDock(true)
        UIView.animate(withDuration: 0.42, animations: {
            arriving.view.alpha = 1
            for old in leaving { old.view.alpha = 0 }
        }, completion: { _ in
            for old in leaving { self.dismount(old) }
        })
        refreshSpin()
    }

    func swap(to index: Int) {
        guard !shifting, halls.indices.contains(index), index != hall else { return }
        let leaving = stack.last
        hall = index
        let arriving = stack.last
        if let arriving {
            if arriving.parent == nil { mount(arriving) }
            arriving.view.isHidden = false
            arriving.view.alpha = 0
            arriving.awaken()
            dressDock(for: arriving)
            UIView.animate(withDuration: 0.2) {
                arriving.view.alpha = 1
                leaving?.view.alpha = 0
            } completion: { _ in
                leaving?.view.isHidden = true
            }
        }
        Deck.shared.cue(Canvas.tabSwitchCue, gain: 0.7)
        refreshSpin()
    }

    func go(_ next: Stage) {
        guard !shifting else { return }
        shifting = true
        let leaving = stack.last
        stack.append(next)
        mount(next)
        next.view.alpha = 0
        next.view.transform = CGAffineTransform(translationX: 0, y: 26).scaledBy(x: 0.97, y: 0.97)
        dressDock(for: next)
        Deck.shared.cue(Canvas.windowOpenCue, gain: 0.7)
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut, animations: {
            next.view.alpha = 1
            next.view.transform = .identity
            leaving?.view.alpha = 0
            leaving?.view.transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
        }, completion: { _ in
            leaving?.view.isHidden = true
            self.shifting = false
        })
        refreshSpin()
    }

    func back() {
        guard !shifting, stack.count > 1 else { return }
        shifting = true
        var line = stack
        let leaving = line.removeLast()
        stack = line
        let arriving = line.last
        arriving?.view.isHidden = false
        arriving?.awaken()
        if let arriving { dressDock(for: arriving) }
        Deck.shared.cue(Canvas.windowCloseCue, gain: 0.7)
        UIView.animate(withDuration: 0.26, delay: 0, options: .curveEaseIn, animations: {
            leaving.view.alpha = 0
            leaving.view.transform = CGAffineTransform(translationX: 0, y: 22)
            arriving?.view.alpha = 1
            arriving?.view.transform = .identity
        }, completion: { _ in
            self.dismount(leaving)
            self.shifting = false
        })
        refreshSpin()
    }

    /// Unwinds the current hall to its root, used when a run ends.
    func homeward() {
        guard stack.count > 1 else { return }
        let keep = stack.first
        let leaving = Array(stack.dropFirst())
        stack = keep.map { [$0] } ?? []
        keep?.view.isHidden = false
        keep?.view.alpha = 0
        keep?.view.transform = .identity
        keep?.awaken()
        if let keep { dressDock(for: keep) }
        UIView.animate(withDuration: 0.34, animations: {
            keep?.view.alpha = 1
            for old in leaving { old.view.alpha = 0 }
        }, completion: { _ in
            for old in leaving { self.dismount(old) }
        })
        refreshSpin()
    }

    var crown: Stage? { stack.last }

    /// Puts a dot on the daily tab when a reward is sitting there.
    func markDaily(_ ready: Bool) {
        dock.flag(daily: ready)
    }

    private func dressDock(for stage: Stage) {
        showDock(!stage.hidesDock)
        dock.light(hall)
    }

    private func showDock(_ wanted: Bool) {
        dockDrop.constant = wanted ? -Dock.height : 0
        UIView.animate(withDuration: 0.22) { self.view.layoutIfNeeded() }
    }

    private func mount(_ stage: Stage) {
        addChild(stage)
        stage.view.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(stage.view, belowSubview: dock)
        NSLayoutConstraint.activate([
            stage.view.topAnchor.constraint(equalTo: view.topAnchor),
            stage.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stage.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stage.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        stage.didMove(toParent: self)
    }

    private func dismount(_ stage: Stage) {
        stage.willMove(toParent: nil)
        stage.view.removeFromSuperview()
        stage.removeFromParent()
    }

    private func refreshSpin() {
        if #available(iOS 16.0, *) {
            setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}
