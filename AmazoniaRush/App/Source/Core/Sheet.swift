import UIKit

/// The panel that slides up between rooms: a blessing to pick, a fork to
/// choose, a camp to rest at, or the end of the run. One at a time, always
/// from the bottom, always over a dimmed board.
final class Sheet: UIView {
    private let veil = UIView()
    private let card = Slab(.raised)
    private let heading = chisel("", Scribe.carved(19, .bold), Hide.gild, lines: 2, align: .center)
    private let blurb = chisel("", Scribe.plain(12), Hide.murmur, lines: 0, align: .center)
    private let body = UIStackView()
    private var lift: NSLayoutConstraint!
    private var shown = false

    init() {
        super.init(frame: .zero)
        isHidden = true
        veil.backgroundColor = Hide.pitch.withAlphaComponent(0.72)
        veil.pin(into: self)

        body.axis = .vertical
        body.spacing = Grid.gap

        let column = UIStackView(arrangedSubviews: [heading, blurb, body])
        column.axis = .vertical
        column.spacing = Grid.tight
        column.setCustomSpacing(Grid.inset, after: blurb)
        column.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(column)
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)

        lift = card.topAnchor.constraint(equalTo: bottomAnchor)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Grid.gutter),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Grid.gutter),
            lift,
            column.topAnchor.constraint(equalTo: card.topAnchor, constant: Grid.gutter),
            column.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Grid.inset),
            column.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Grid.inset),
            column.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Grid.gutter),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func install(over host: UIView) {
        pin(into: host)
    }

    // --- the three shapes it takes ----------------------------------------

    /// A statement with one way forward, and optionally things to buy first.
    func tell(
        title: String,
        blurb line: String,
        deed: String,
        picks: [(String, String, Bool, () -> Void)] = [],
        go: @escaping () -> Void
    ) {
        dress(title, line)
        for pick in picks {
            body.addArrangedSubview(carve(Ledge(
                title: pick.0,
                blurb: pick.1,
                cast: pick.2 ? .raised : .sunk,
                deed: Vault.say(Lexeme.navBuy),
                deedBuild: pick.2 ? .gold : .ghost,
                deedLive: pick.2,
                fire: pick.3
            )))
        }
        let pad = PressPad(.gold)
        pad.dress(deed)
        pad.onPress = go
        pad.measure(nil, Grid.touch + 6)
        body.addArrangedSubview(pad)
        raise()
    }

    /// One of several. `keys` renumbers the picks when some are missing.
    func choose(
        title: String,
        blurb line: String,
        picks: [(String, String)],
        keys: [Int]? = nil,
        pick: @escaping (Int) -> Void
    ) {
        dress(title, line)
        for (slot, option) in picks.enumerated() {
            let key = keys?.indices.contains(slot) == true ? keys![slot] : slot
            body.addArrangedSubview(carve(Ledge(
                title: option.0,
                blurb: option.1,
                cast: .lit,
                deed: Vault.say(Lexeme.navConfirm),
                deedBuild: .gold,
                deedWide: 96,
                fire: { pick(key) }
            )))
        }
        raise()
    }

    /// A yes or no the player cannot fumble by accident.
    func ask(
        title: String,
        blurb line: String,
        yes: String,
        no: String,
        answer: @escaping (Bool) -> Void
    ) {
        dress(title, line)
        let nope = PressPad(.ghost)
        nope.dress(no)
        nope.onPress = { [weak self] in
            self?.dismiss()
            answer(false)
        }
        let yep = PressPad(.danger)
        yep.dress(yes)
        yep.onPress = { [weak self] in
            self?.dismiss()
            answer(true)
        }
        let row = UIStackView(arrangedSubviews: [nope, yep])
        row.axis = .horizontal
        row.spacing = Grid.gap
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: Grid.touch + 6).isActive = true
        body.addArrangedSubview(row)
        raise()
    }

    func dismiss() {
        guard shown else { return }
        shown = false
        lift.constant = 0
        UIView.animate(withDuration: 0.22, animations: {
            self.veil.alpha = 0
            self.superview?.layoutIfNeeded()
        }, completion: { _ in
            self.isHidden = true
        })
    }

    // --- plumbing ----------------------------------------------------------

    private func dress(_ title: String, _ line: String) {
        heading.text = title
        blurb.text = line
        blurb.isHidden = line.isEmpty
        for spare in body.arrangedSubviews {
            body.removeArrangedSubview(spare)
            spare.removeFromSuperview()
        }
    }

    private func raise() {
        superview?.bringSubviewToFront(self)
        isHidden = false
        superview?.layoutIfNeeded()
        shown = true
        veil.alpha = 0
        lift.constant = -card.systemLayoutSizeFitting(
            CGSize(width: bounds.width - Grid.gutter * 2, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height - Grid.gutter
        UIView.animate(withDuration: 0.28, delay: 0, options: .curveEaseOut) {
            self.veil.alpha = 1
            self.superview?.layoutIfNeeded()
        }
    }
}
