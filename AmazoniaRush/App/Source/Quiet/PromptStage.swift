import UIKit
import UserNotifications

/// The notification prompt, shown before the quiet side is entered.
///
/// The painted plate already carries the wording, so this screen adds only
/// the two ways forward and leaves the picture intact. It is a screen rather
/// than a bare system dialog because the player should be able to read what
/// they are agreeing to, and because iOS raises that dialog exactly once:
/// this screen decides when the one chance is spent.
///
/// Waving it away hides it for a cooldown, not forever. A system refusal is
/// permanent and is respected above everything else.
final class PromptStage: Stage {
    override var orientationWish: UIInterfaceOrientationMask { .allButUpsideDown }
    override var wantsPurse: Bool { false }
    override var hidesDock: Bool { true }
    override var playsAudio: Bool { false }

    /// Called when the screen is finished with, either way.
    var onDone: ((Bool) -> Void)?

    private let plate = UIImageView()
    private let accept = PressPad(.gold)
    private let decline = PressPad(.stone)
    private let pads = UIStackView()

    /// The buttons' width. Portrait runs the full width (less the gutters);
    /// landscape is 30% shorter, so the controls are not stretched across a
    /// very wide screen. Both buttons share one width, so they stay matched.
    private var padsWidthFull: NSLayoutConstraint!
    private var padsWidthShort: NSLayoutConstraint!

    override func assemble() {
        view.backgroundColor = Hide.pitch

        plate.contentMode = .scaleAspectFill
        plate.clipsToBounds = true
        plate.pin(into: view)

        accept.dress(Vault.say(Lexeme.gatePermitAccept))
        accept.build = .gold
        accept.onPress = { [weak self] in self?.ask() }
        accept.translatesAutoresizingMaskIntoConstraints = false

        decline.dress(Vault.say(Lexeme.gatePermitLater))
        decline.onPress = { [weak self] in self?.later() }
        decline.translatesAutoresizingMaskIntoConstraints = false

        pads.axis = .vertical
        pads.spacing = Grid.gap
        // Centre the buttons so they sit in the middle of the screen in both
        // orientations rather than filling the width edge to edge; their own
        // width constraint is what sizes them.
        pads.alignment = .center
        pads.translatesAutoresizingMaskIntoConstraints = false
        pads.addArrangedSubview(accept)
        pads.addArrangedSubview(decline)
        view.addSubview(pads)

        // The buttons fill the stack's width in portrait and are 30% shorter in
        // landscape. Both are measured against the same stack width, so
        // landscape is exactly 70% of the full portrait length. Decline always
        // matches accept, so the two stay the same length.
        padsWidthFull = accept.widthAnchor.constraint(equalTo: pads.widthAnchor)
        padsWidthShort = accept.widthAnchor.constraint(
            equalTo: pads.widthAnchor, multiplier: 0.7
        )

        NSLayoutConstraint.activate([
            pads.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Grid.gutter + 6),
            pads.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Grid.gutter - 6),
            pads.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Grid.gutter
            ),
            accept.heightAnchor.constraint(equalToConstant: Grid.touch + 6),
            decline.heightAnchor.constraint(equalToConstant: Grid.touch),
            decline.widthAnchor.constraint(equalTo: accept.widthAnchor),
        ])

        applyButtonWidth(wide: view.bounds.width > view.bounds.height)
        dressPlate(view.bounds.size)
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.dressPlate(size)
            self.applyButtonWidth(wide: size.width > size.height)
        }, completion: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyButtonWidth(wide: view.bounds.width > view.bounds.height)
    }

    /// Switches the buttons between their full portrait width and the
    /// 30%-shorter landscape width, guarding so repeated layout passes do no
    /// needless work.
    private func applyButtonWidth(wide: Bool) {
        if wide {
            guard !padsWidthShort.isActive else { return }
            padsWidthFull.isActive = false
            padsWidthShort.isActive = true
        } else {
            guard !padsWidthFull.isActive else { return }
            padsWidthShort.isActive = false
            padsWidthFull.isActive = true
        }
    }

    /// Each orientation has its own painting, and the plates carry the words
    /// already, so nothing is drawn twice.
    private func dressPlate(_ size: CGSize) {
        let wide = size.width > size.height
        plate.image = Vault.plate(wide ? Canvas.gatePermitWidePlate : Canvas.gatePermitUprightPlate)
    }

    /// The player agreed: spend the one system dialog iOS will allow. Tapping
    /// Accept retires this screen for good right here, before the system
    /// dialog is even raised, so it never returns no matter what the player
    /// then picks in that dialog.
    private func ask() {
        accept.isEnabled = false
        decline.isEnabled = false
        Hearth.shared.promptAccepted()
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { _, _ in
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
                self.onDone?(true)
            }
        }
    }

    /// The player waved it away: the prompt returns on a later launch, after
    /// the ~3-day cooldown.
    private func later() {
        Hearth.shared.promptAnswered()
        onDone?(true)
    }
}
