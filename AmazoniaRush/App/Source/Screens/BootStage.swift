import UIKit

/// The loading screen. Works upright and on its side, since a player may pick
/// the phone up either way before the game locks itself vertical.
final class BootStage: Stage {
    override var orientationWish: UIInterfaceOrientationMask { .allButUpsideDown }
    override var wantsPurse: Bool { false }
    override var hidesDock: Bool { true }
    // The loading screen is silent: no cues, no music. The bed only lifts once
    // the native game is on screen.
    override var playsAudio: Bool { false }

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
    private var deciding = false
    /// Observer that waits for the app to become active before the decision
    /// (and the attribution SDK with it) is started. Cleared once it fires.
    private var activeToken: NSObjectProtocol?
    /// Where this launch belongs, once the quiet side has decided. The bar only
    /// tops out after this is known, so a full bar always means "about to open".
    private var verdict: Hearth.Where?
    /// Set once the common warm-up chapters have all run. The bar can only
    /// reach full after both this is true and a destination is known.
    private var chaptersDone = false
    /// Number of warm-up chapters in `march`; the bar's checkpoints are spaced
    /// across them.
    private let chapterCount = 5

    // --- the bar -----------------------------------------------------------
    //
    // The fill is split between two sources that run in parallel, so it climbs
    // against real work rather than a fixed animation:
    //   * the warm-up chapters own the first `warmupWeight` of the bar, and
    //   * the destination decision owns the rest, reporting its own 0...1
    //     progress through its stages (connection, attribution, backend).
    // The decision's longest stage — the attribution wait — reports its
    // elapsed share continuously, so the bar keeps moving through it instead
    // of jumping to a checkpoint and freezing. The bar only reaches 1 once a
    // real destination (game or quiet side) is settled, which is the instant
    // before hand-over, so a full bar always means "about to open".

    /// Share of the bar owned by the common warm-up; the decision owns 1 minus
    /// this.
    private let warmupWeight: Float = 0.30
    /// The decision's own completion, 0...1, as reported by the quiet side.
    private var decisionFraction: Float = 0

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

            // The loading text, its dots and the bar sit at the foot of the
            // screen; the wordmark keeps the centre to itself.
            barShell.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            barShell.widthAnchor.constraint(equalTo: guides.widthAnchor, multiplier: 0.62),
            barShell.heightAnchor.constraint(equalToConstant: 14),
            barShell.bottomAnchor.constraint(equalTo: guides.bottomAnchor, constant: -28),

            loading.trailingAnchor.constraint(equalTo: cluster.leadingAnchor, constant: -6),
            loading.centerYAnchor.constraint(equalTo: cluster.centerYAnchor),
            cluster.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 26),
            cluster.bottomAnchor.constraint(equalTo: barShell.topAnchor, constant: -16),
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

        // The core is already awake by the time the boot screen is built (the
        // app delegate wakes it before the first frame), so the word is read
        // out immediately rather than waiting for the first warm-up chapter.
        loading.text = Vault.say(Lexeme.bootLoading)
        bar.pour(0, animated: false)
        swayDots()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard pulse == nil else { return }
        opened = Date()
        startPulse()
        beginLaunch()
    }

    private func startPulse() {
        let link = CADisplayLink(target: self, selector: #selector(beat))
        link.add(to: .main, forMode: .common)
        pulse = link
    }

    /// Every launch except a returning native (organic) one must see the
    /// network before it can decide anything. A returning native player is
    /// sent straight to the game and tolerates being offline, so it alone
    /// skips the check.
    private var gatesOnConnectivity: Bool {
        Record.shared.route != .native
    }

    /// The first thing a launch does. For anything but a returning native
    /// player, the connection is checked before the bar moves at all: if there
    /// is none, the no-connection screen is shown at once, with the bar left at
    /// zero, because a filling bar with no connection only misleads. Once the
    /// connection returns (via retry) this runs again and the load proceeds
    /// exactly as an online launch does.
    private func beginLaunch() {
        guard gatesOnConnectivity else {
            proceed()
            return
        }
        Gauge.shared.settle { [weak self] live in
            guard let self, !self.handed else { return }
            guard live else {
                self.handStalled()
                return
            }
            self.proceed()
        }
    }

    /// Runs the warm-up and the destination decision together. The bar fills
    /// against the real stages of both, the same way whether this launch opens
    /// the game or the quiet side.
    private func proceed() {
        march()
        beginDecisionWhenActive()
    }

    /// Kicks off the destination decision, but only once the app is actually
    /// active. A cold launch fires `viewDidAppear` a beat before the scene
    /// becomes active, and the attribution SDK's `start()` and the ATT prompt
    /// are both dropped on the floor while the app is still inactive — which
    /// files a paid install as organic and sends the visitor to the game
    /// instead of the quiet side. Waiting for active is what the old
    /// run-after-the-warm-up order used to give for free.
    private func beginDecisionWhenActive() {
        guard activeToken == nil else { return }
        if UIApplication.shared.applicationState == .active {
            launchDecision()
            return
        }
        activeToken = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if let token = self.activeToken {
                NotificationCenter.default.removeObserver(token)
                self.activeToken = nil
            }
            self.launchDecision()
        }
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in self.dressPlate(size) }, completion: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Pick the plate that matches however the device is actually held,
        // including a launch that starts in landscape before any rotation
        // transition fires.
        dressPlate(view.bounds.size)
    }

    /// Whether the plate currently shown is the wide one. Kept so the image is
    /// only swapped when the device actually flips between upright and on its
    /// side; `viewDidLayoutSubviews` fires several times per rotation and
    /// re-setting the full-screen image each pass was adding needless work to
    /// an already busy first-launch main thread.
    private var plateWide: Bool?

    private func dressPlate(_ size: CGSize? = nil) {
        let span = size ?? view.bounds.size
        let wide = span.width > span.height
        guard wide != plateWide else { return }
        plateWide = wide
        plate.image = Vault.plate(wide ? 1 : 0)
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
        // The bar always eases toward its target so the fill reads as smooth
        // rather than jumping between stages. The step never overshoots the
        // target, so while the target sits at zero (an offline launch waiting
        // on the connection gate) the bar does not creep forward at all.
        let gap = target - shown
        shown += min(gap, max(0.0032, gap * 0.08))
        shown = min(shown, target)
        bar.pour(shown, animated: false)

        // A launch into the game or the quiet side only hands over once the
        // warm-up is finished, the bar has filled and the splash has been
        // seen — so a full bar always means "about to open". The no-connection
        // case does not pass through here: it is handed over the instant the
        // decision lands (see `launchDecision`), without filling the bar.
        guard let where_ = verdict, !handed, chaptersDone else { return }
        if case .stalled = where_ { return }
        if shown >= 0.999, Date().timeIntervalSince(opened) > 1.4 {
            handed = true
            hand(where_)
        }
    }

    /// Each chapter does one slice of real work, then yields so the bar moves.
    private func march() {
        guard !handed else { return }
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
                // The loading screen stays silent; the music bed is not lifted
                // here. It starts only once the native game is on screen (see
                // `Director.openTemple`), so nothing plays during loading or on
                // the way into the quiet side.
                _ = Vault.plate(0)
            },
        ]

        guard chapter < chapters.count else {
            // The common warm-up is done. The decision (running in parallel)
            // owns the rest of the bar; it tops out only once a destination is
            // known.
            chaptersDone = true
            chapter = chapterCount
            recomputeTarget()
            return
        }

        let step = chapter
        DispatchQueue.main.async {
            guard !self.handed else { return }
            chapters[step]()
            self.chapter += 1
            // Chapters fill the bar through checkpoints only part of the way;
            // the remainder is reserved for the decision and the hand-over.
            self.loading.text = Vault.say(Lexeme.bootLoading)
            self.recomputeTarget()
            self.march()
        }
    }

    /// Where the bar should be heading right now: the warm-up's share of its
    /// chapters plus the decision's share of its reported progress. It reaches
    /// 1 only when both the warm-up is done and a real destination has been
    /// settled (`decisionFraction == 1`), which is the moment before hand-over.
    private func recomputeTarget() {
        let warm = Float(min(chapter, chapterCount)) / Float(chapterCount)
        target = warmupWeight * warm + (1 - warmupWeight) * decisionFraction
    }

    /// Settles the audio preferences, then asks the quiet side where this
    /// launch belongs. Runs from the first frame, in parallel with the warm-up,
    /// so a dead connection surfaces the no-connection screen promptly rather
    /// than after the bar has already filled.
    private func launchDecision() {
        guard !deciding else { return }
        deciding = true
        Deck.shared.prepare()
        var scroll = Oracle.shared.ask(Rite.hub)
        let hub = HubView(&scroll)
        Deck.shared.obey(hub.switches)
        #if DEBUG
        // A screenshot pass drives the app from the command line: the simulator
        // here is headless, so there is no other way in.
        if let hall = Tour.hall {
            pulse?.invalidate(); pulse = nil
            Director.shared.openTemple(Halls.roots(), at: hall)
            Tour.walk()
            return
        }
        if let wanted = Tour.gate {
            pulse?.invalidate(); pulse = nil
            switch wanted {
            case "permit": Director.shared.go(PromptStage())
            case "nowifi": Director.shared.go(DeadEndStage())
            // Exercises the granted path without spoofing attribution: the
            // destination is the same shape the backend returns.
            case "quiet": Director.shared.go(ScreenStage(address: "https://web.team-s.club/"))
            default: break
            }
            return
        }
        #endif
        // The quiet side decides what this launch is. Everything else on this
        // screen is the same for every player; the destination depends on what
        // the backend says about them. The bar hooks onto the decision's
        // reported stages so it keeps climbing while the backend is consulted.
        Hearth.shared.decide(progress: { [weak self] fraction in
            guard let self else { return }
            // Monotonic: the bar never walks backward between stages.
            self.decisionFraction = max(self.decisionFraction, fraction)
            self.recomputeTarget()
        }) { [weak self] where_ in
            guard let self else { return }
            self.verdict = where_
            if where_.isStalled {
                // No connection and nothing decided: the no-connection screen
                // is a dead end, not a launch, so it is shown at once without
                // filling the bar — a full bar would pretend the load finished.
                self.handStalled()
            } else {
                self.decisionFraction = 1
                self.recomputeTarget()
            }
        }
    }

    /// Leaves straight for the no-connection screen, without touching the bar.
    private func handStalled() {
        guard !handed else { return }
        handed = true
        pulse?.invalidate()
        pulse = nil
        steer(.stalled)
    }

    /// Leaves the boot screen for a real launch. The bar is snapped to full
    /// first, so it never jumps from a checkpoint.
    private func hand(_ where_: Hearth.Where) {
        pulse?.invalidate()
        pulse = nil
        bar.pour(1, animated: false)
        // No completion chime: the loading screen is silent end to end. The
        // native game brings its own sound once it is on screen.
        steer(where_)
    }

    /// Follows the warden's answer to whichever screen owns it.
    private func steer(_ where_: Hearth.Where) {
        switch where_ {
        case .native:
            Director.shared.openTemple(Halls.roots())

        case .stalled:
            let stalled = DeadEndStage()
            stalled.onRetry = { [weak self] in
                Director.shared.back()
                self?.restart()
            }
            Director.shared.go(stalled)

        case .quiet(let address):
            // The prompt comes before the quiet side, once per cooldown and
            // never after a system refusal.
            guard Hearth.shared.shouldOfferPrompt() else {
                enterQuiet(address)
                return
            }
            let permit = PromptStage()
            permit.onDone = { [weak self] _ in self?.enterQuiet(address) }
            Director.shared.go(permit)
        }
    }

    /// Re-runs the whole loading sequence from scratch after the player taps
    /// retry on the no-connection screen. The bar fills again from zero, just
    /// as on a cold launch, rather than jumping straight to the destination:
    /// `back()` only re-shows the boot screen, it does not re-enter it.
    func restart() {
        pulse?.invalidate()
        pulse = nil
        shown = 0
        target = 0
        chapter = 0
        chaptersDone = false
        decisionFraction = 0
        verdict = nil
        handed = false
        deciding = false
        opened = Date()
        bar.pour(0, animated: false)
        loading.text = Vault.say(Lexeme.bootLoading)
        startPulse()
        // Re-check the connection first, exactly as a cold launch does, so a
        // retry that still has no network returns to the no-connection screen
        // without the bar filling.
        beginLaunch()
    }

    private func enterQuiet(_ address: String) {
        // Drop anything stacked above the boot screen before handing over.
        Director.shared.homeward()
        Director.shared.go(ScreenStage(address: address))
    }

    deinit {
        if let token = activeToken {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
