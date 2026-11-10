import UIKit

/// Shown when the backend could not be reached and nothing has been decided
/// yet. The plate carries the wording; this screen adds the one control that
/// matters, so a player on a dead connection gets an honest answer promptly
/// instead of a spinner that never resolves.
///
/// Retrying runs the whole decision again: the connection is re-checked, the
/// attribution answer re-awaited and the backend asked afresh. Nothing is
/// replayed from cache, which is what makes the control mean something.
final class DeadEndStage: Stage {
    override var orientationWish: UIInterfaceOrientationMask { .allButUpsideDown }
    override var wantsPurse: Bool { false }
    override var hidesDock: Bool { true }
    override var playsAudio: Bool { false }

    /// Called when the player wants another attempt.
    var onRetry: (() -> Void)?

    private let plate = UIImageView()
    private let retry = PressPad(.gold)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var strip: UIStackView!

    /// The retry button's width. Portrait runs the full width (less the room
    /// the spinner needs beside it); landscape is 30% shorter, so one control
    /// is not stretched across a very wide screen.
    private var retryWidthFull: NSLayoutConstraint!
    private var retryWidthShort: NSLayoutConstraint!
    /// Room kept to the right of the button for the spinner (its width plus the
    /// gap), so the two never overlap in either width.
    private static let spinnerReserve: CGFloat = Grid.gap + 20

    override func assemble() {
        view.backgroundColor = Hide.pitch

        plate.contentMode = .scaleAspectFill
        plate.clipsToBounds = true
        plate.pin(into: view)

        retry.dress(Vault.say(Lexeme.gateNowifiRetry))
        retry.onPress = { [weak self] in self?.attempt() }
        retry.translatesAutoresizingMaskIntoConstraints = false

        spinner.color = Hide.gild
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false

        // The spinner sits beside the pad rather than under it, so the button
        // never moves while an attempt is in flight.
        let row = UIStackView(arrangedSubviews: [retry, spinner])
        row.axis = .horizontal
        row.spacing = Grid.gap
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false

        strip = UIStackView(arrangedSubviews: [row])
        strip.axis = .vertical
        // Hug the row to its content so the button's own width constraint is
        // what sizes it, rather than the stack stretching it to fill, and
        // centre it so the button sits in the middle of the screen in both
        // orientations rather than clinging to the leading edge.
        strip.alignment = .center
        strip.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(strip)

        // The button fills the strip (less the spinner's room) in portrait, and
        // is 30% shorter in landscape. Both are measured against the same strip
        // width, so landscape is exactly 70% of the full portrait length.
        retryWidthFull = retry.widthAnchor.constraint(
            equalTo: strip.widthAnchor, constant: -Self.spinnerReserve
        )
        retryWidthShort = retry.widthAnchor.constraint(
            equalTo: strip.widthAnchor, multiplier: 0.7, constant: -0.7 * Self.spinnerReserve
        )

        NSLayoutConstraint.activate([
            strip.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Grid.gutter + 6),
            strip.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Grid.gutter - 6),
            strip.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Grid.gutter
            ),
            retry.heightAnchor.constraint(equalToConstant: Grid.touch + 6),
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

    private func dressPlate(_ size: CGSize) {
        let wide = size.width > size.height
        plate.image = Vault.plate(wide ? Canvas.gateDarkWidePlate : Canvas.gateDarkUprightPlate)
    }

    /// Switches the button between its full portrait width and the 30%-shorter
    /// landscape width, guarding so repeated layout passes do no needless work.
    private func applyButtonWidth(wide: Bool) {
        if wide {
            guard !retryWidthShort.isActive else { return }
            retryWidthFull.isActive = false
            retryWidthShort.isActive = true
        } else {
            guard !retryWidthFull.isActive else { return }
            retryWidthShort.isActive = false
            retryWidthFull.isActive = true
        }
    }

    /// Hands the attempt back to the warden, showing that something is
    /// happening so a slow retry does not read as a dead control.
    private func attempt() {
        retry.isEnabled = false
        spinner.startAnimating()
        Gauge.shared.settle { _ in
            self.spinner.stopAnimating()
            self.retry.isEnabled = true
            self.onRetry?()
        }
    }
}
