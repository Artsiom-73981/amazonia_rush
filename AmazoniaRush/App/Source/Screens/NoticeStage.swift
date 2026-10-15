import UIKit

/// The story, told between chambers. One painted card per chapter: the place
/// you are walking into, a few lines about it, and a way on. It is an overlay
/// rather than a screen so it can sit on top of whatever raised it without
/// disturbing the stack underneath.
final class Saga {
    static let shared = Saga()

    private var card: UIView?

    /// Each chapter is shown against the chamber art of its own region.
    private static let plates = [
        Canvas.aUniversalBgEntranceScene,
        Canvas.bBgOasisShrineScene,
        Canvas.bBgRuinedTempleHallScene,
        Canvas.bBgPyramidCoreChamberScene,
        Canvas.bBgObservatoryScene,
        Canvas.bBgUndergroundMechanismComplexScene,
        Canvas.bBgGreatWheelOfMaatChamberScene,
    ]

    /// The chapter opening, shown on the way into a region.
    func open(chapter: Int, then: @escaping () -> Void) {
        raise(chapter: chapter, tail: nil, then: then)
    }

    /// The chapter's last word, shown when a descent ends either way.
    func show(chapter: Int, won: Bool, then: @escaping () -> Void) {
        raise(chapter: chapter, tail: won ? Lexeme.sagaWon : Lexeme.sagaLost, then: then)
    }

    private func raise(chapter: Int, tail: UInt16?, then: @escaping () -> Void) {
        guard card == nil, let host = Director.shared.view else {
            then()
            return
        }
        let seat = max(0, min(Lexeme.sagaTitleAll.count - 1, chapter))

        let sheet = UIView()
        sheet.backgroundColor = Hide.pitch
        sheet.alpha = 0
        sheet.pin(into: host)

        let plate = UIImageView(image: Vault.scene(Saga.plates[seat % Saga.plates.count]))
        plate.contentMode = .scaleAspectFill
        plate.clipsToBounds = true
        plate.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(plate)

        // The painting fades into the page rather than ending on a hard edge.
        let veil = CAGradientLayer()
        veil.colors = [
            Hide.pitch.withAlphaComponent(0).cgColor,
            Hide.pitch.withAlphaComponent(0.7).cgColor,
            Hide.pitch.cgColor,
        ]
        veil.locations = [0, 0.55, 1]
        let curtain = UIView()
        curtain.translatesAutoresizingMaskIntoConstraints = false
        curtain.layer.addSublayer(veil)
        sheet.addSubview(curtain)

        let chapterTag = chisel(
            Vault.say(Lexeme.sagaChapter)
                .replacingOccurrences(of: "%1", with: "\(seat + 1)")
                .replacingOccurrences(of: "%2", with: "\(Lexeme.sagaTitleAll.count)"),
            Scribe.tally(12),
            Hide.brass,
            align: .center
        )
        let heading = chisel(
            Vault.say(Lexeme.sagaTitleAll[seat]),
            Scribe.carved(26, .bold),
            Hide.gild,
            lines: 2,
            align: .center
        )
        var tale = Vault.say(Lexeme.sagaBodyAll[seat])
        if let tail {
            tale += "\n\n" + Vault.say(tail)
        }
        let body = chisel(tale, Scribe.plain(15), Hide.parchment, lines: 0, align: .center)

        let onward = PressPad(.gold)
        onward.dress(Vault.say(Lexeme.navContinue))
        onward.onPress = { [weak self] in self?.lower(then) }
        onward.translatesAutoresizingMaskIntoConstraints = false

        let column = UIStackView(arrangedSubviews: [chapterTag, heading, body, onward])
        column.axis = .vertical
        column.spacing = 16
        column.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(column)

        NSLayoutConstraint.activate([
            plate.topAnchor.constraint(equalTo: sheet.topAnchor),
            plate.leadingAnchor.constraint(equalTo: sheet.leadingAnchor),
            plate.trailingAnchor.constraint(equalTo: sheet.trailingAnchor),
            plate.heightAnchor.constraint(equalTo: sheet.heightAnchor, multiplier: 0.62),
            curtain.leadingAnchor.constraint(equalTo: sheet.leadingAnchor),
            curtain.trailingAnchor.constraint(equalTo: sheet.trailingAnchor),
            curtain.bottomAnchor.constraint(equalTo: plate.bottomAnchor),
            curtain.heightAnchor.constraint(equalTo: plate.heightAnchor, multiplier: 0.6),
            column.leadingAnchor.constraint(equalTo: sheet.leadingAnchor, constant: Grid.gutter + 6),
            column.trailingAnchor.constraint(equalTo: sheet.trailingAnchor, constant: -Grid.gutter - 6),
            column.bottomAnchor.constraint(
                equalTo: sheet.safeAreaLayoutGuide.bottomAnchor, constant: -Grid.gutter
            ),
            onward.heightAnchor.constraint(equalToConstant: Grid.touch),
        ])
        sheet.layoutIfNeeded()
        veil.frame = curtain.bounds

        card = sheet
        Deck.shared.cue(Canvas.windowOpenCue, gain: 0.6)
        UIView.animate(withDuration: 0.4) { sheet.alpha = 1 }
    }

    private func lower(_ then: @escaping () -> Void) {
        guard let sheet = card else {
            then()
            return
        }
        card = nil
        UIView.animate(withDuration: 0.26, animations: { sheet.alpha = 0 }) { _ in
            sheet.removeFromSuperview()
            then()
        }
    }
}
