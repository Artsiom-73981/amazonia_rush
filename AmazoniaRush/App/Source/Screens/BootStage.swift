import UIKit

/// The loading screen. Works upright and on its side, since a player may pick
/// the phone up either way before the game locks itself vertical.
final class BootStage: Stage {
    override var orientationWish: UIInterfaceOrientationMask { .allButUpsideDown }
    override var wantsPurse: Bool { false }
    override var hidesDock: Bool { true }

    private let plate = UIImageView()
    private let wordmark = UIImageView()
    private let loading = UILabel()
    private let bar = Meter(thickness: 8)
    private let barShell = Slab(.sunk, corner: 6)
    private var dots: [UIView] = []

    private var pulse: CADisplayLink?
    private var shown: Float = 0
    private var target: Float = 0
    private var chapter = 0
    private var opened = Date()
    private var handed = false

    override func assemble() {
        view.backgroundColor = Hide.pitch

        plate.contentMode = .scaleAspectFill
        plate.clipsToBounds = true
        plate.pin(into: view)
        dressPlate()

        let haze = UIView()
        haze.backgroundColor = Hide.pitch.withAlphaComponent(0.28)
        haze.pin(into: view)

        wordmark.contentMode = .scaleAspectFit
        wordmark.image = Vault.plate(2)
        wordmark.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(wordmark)

        loading.font = Scribe.carved(16, .medium)
        loading.textColor = Hide.gild
        loading.textAlignment = .right
        loading.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loading)

        let cluster = UIStackView()
        cluster.axis = .horizontal
        cluster.spacing = 5
        cluster.alignment = .center
        cluster.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cluster)
        for _ in 0..<3 {
            let pip = UIView()
            pip.backgroundColor = Hide.gild
            pip.layer.cornerRadius = 3
            pip.translatesAutoresizingMaskIntoConstraints = false
            pip.widthAnchor.constraint(equalToConstant: 6).isActive = true
            pip.heightAnchor.constraint(equalToConstant: 6).isActive = true
            cluster.addArrangedSubview(pip)
            dots.append(pip)
        }

        barShell.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(barShell)
        bar.pin(into: barShell, inset: 3)

        let guides = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            wordmark.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            wordmark.bottomAnchor.constraint(equalTo: view.centerYAnchor, constant: -18),
            wordmark.widthAnchor.constraint(lessThanOrEqualTo: guides.widthAnchor, multiplier: 0.78),
            wordmark.heightAnchor.constraint(lessThanOrEqualTo: guides.heightAnchor, multiplier: 0.3),

            loading.trailingAnchor.constraint(equalTo: cluster.leadingAnchor, constant: -6),
            loading.centerYAnchor.constraint(equalTo: cluster.centerYAnchor),
            cluster.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 26),
            cluster.topAnchor.constraint(equalTo: view.centerYAnchor, constant: 6),

            barShell.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            barShell.topAnchor.constraint(equalTo: cluster.bottomAnchor, constant: 22),
            barShell.widthAnchor.constraint(equalTo: guides.widthAnchor, multiplier: 0.62),
            barShell.heightAnchor.constraint(equalToConstant: 14),
        ])

        // Shaped sizing so the mark keeps its aspect on both plates. The width
        // wish yields when the landscape plate is too short for it.
        if let art = wordmark.image {
            let ratio = art.size.height / max(1, art.size.width)
            wordmark.heightAnchor.constraint(
                equalTo: wordmark.widthAnchor, multiplier: ratio
            ).isActive = true
            let wish = wordmark.widthAnchor.constraint(
                equalTo: guides.widthAnchor, multiplier: 0.74
            )
            wish.priority = .defaultHigh
            wish.isActive = true
        }

        // The word itself arrives with the first chapter: until the core is
        // awake there is nothing to read it out of.
        loading.text = ""
        bar.pour(0, animated: false)
        swayDots()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard pulse == nil else { return }
        opened = Date()
        let link = CADisplayLink(target: self, selector: #selector(beat))
        link.add(to: .main, forMode: .common)
        pulse = link
        march()
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in self.dressPlate(size) }, completion: nil)
    }

    private func dressPlate(_ size: CGSize? = nil) {
        let span = size ?? view.bounds.size
        plate.image = Vault.plate(span.width > span.height ? 1 : 0)
    }

    // --- animation ---------------------------------------------------------

    private func swayDots() {
        for (index, pip) in dots.enumerated() {
            let rise = CAKeyframeAnimation(keyPath: "transform")
            rise.values = [
                CATransform3DMakeScale(1, 1, 1),
                CATransform3DMakeScale(1.7, 1.7, 1),
                CATransform3DMakeScale(1, 1, 1),
            ]
            rise.keyTimes = [0, 0.4, 1]
            rise.duration = 0.96
            rise.beginTime = CACurrentMediaTime() + Double(index) * 0.18
            rise.repeatCount = .infinity
            rise.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pip.layer.add(rise, forKey: nil)

            let glow = CABasicAnimation(keyPath: "opacity")
            glow.fromValue = 0.3
            glow.toValue = 1
            glow.duration = 0.48
            glow.beginTime = CACurrentMediaTime() + Double(index) * 0.18
            glow.autoreverses = true
            glow.repeatCount = .infinity
            pip.layer.add(glow, forKey: nil)
        }
    }

    @objc private func beat() {
        // The bar always walks toward its target so the fill reads as smooth
        // rather than jumping between stages.
        let gap = target - shown
        shown += max(0.0032, gap * 0.08)
        shown = min(shown, target)
        bar.pour(shown, animated: false)

        if shown >= 0.999, !handed, Date().timeIntervalSince(opened) > 1.9 {
            handed = true
            hand()
        }
    }

    /// Each chapter does one slice of real work, then yields so the bar moves.
    private func march() {
        let chapters: [() -> Void] = [
            {
                Deck.shared.prepare()
                Oracle.shared.awaken()
            },
            {
                Vault.learnAll()
            },
            {
                _ = Oracle.shared.heartbeat()
                Oracle.shared.preserve()
            },
            {
                Deck.shared.warm([
                    Canvas.buttonClickCue,
                    Canvas.windowOpenCue,
                    Canvas.windowCloseCue,
                    Canvas.coinPickupCue,
                ])
            },
            {
                _ = Vault.plate(0)
                Deck.shared.liftBed()
            },
        ]

        guard chapter < chapters.count else {
            target = 1
            return
        }

        let step = chapter
        DispatchQueue.main.async {
            chapters[step]()
            self.chapter += 1
            self.target = Float(self.chapter) / Float(chapters.count) * 0.97
            self.loading.text = Vault.say(Lexeme.bootLoading)
            self.march()
        }
    }

    private func hand() {
        pulse?.invalidate()
        pulse = nil
        Deck.shared.cue(Canvas.loadingCompleteCue, gain: 0.8)
        var scroll = Oracle.shared.ask(Rite.hub)
        let hub = HubView(&scroll)
        Deck.shared.obey(hub.switches)
        #if DEBUG
        // A screenshot pass drives the app from the command line: the
        // simulator here is headless, so there is no other way in.
        if let hall = Tour.hall {
            Director.shared.openTemple(Halls.roots(), at: hall)
            Tour.walk()
            return
        }
        #endif
        // Straight into the game. The player is never asked for anything:
        // there are no notifications in this build, so no system prompt
        // exists to postpone.
        Director.shared.openTemple(Halls.roots())
    }
}
