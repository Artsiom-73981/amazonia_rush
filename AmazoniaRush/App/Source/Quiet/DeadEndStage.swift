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

    /// Called when the player wants another attempt.
    var onRetry: (() -> Void)?

    private let plate = UIImageView()
    private let retry = PressPad(.gold)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var strip: UIStackView!

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
        strip.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(strip)

        NSLayoutConstraint.activate([
            strip.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Grid.gutter + 6),
            strip.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Grid.gutter - 6),
            strip.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Grid.gutter
            ),
            retry.heightAnchor.constraint(equalToConstant: Grid.touch + 6),
        ])

        dressPlate(view.bounds.size)
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in self.dressPlate(size) }, completion: nil)
    }

    private func dressPlate(_ size: CGSize) {
        let wide = size.width > size.height
        plate.image = Vault.plate(wide ? Canvas.gateDarkWidePlate : Canvas.gateDarkUprightPlate)
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
