import UIKit

/// One tab in the dock: a mark, a word and a dot for "something is waiting".
final class DockTab: UIControl {
    private let mark = UIImageView()
    private let caption = UILabel()
    private let bead = UIView()

    private let leaf: UInt16
    var lit = false { didSet { redress() } }
    var waiting = false { didSet { bead.isHidden = !waiting } }

    init(_ prop: Int, _ leaf: UInt16) {
        self.leaf = leaf
        super.init(frame: .zero)
        mark.image = Vault.prop(prop)
        mark.contentMode = .scaleAspectFit
        mark.isUserInteractionEnabled = false
        mark.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mark)

        caption.text = Vault.say(leaf)
        caption.font = Scribe.plain(10, .semibold)
        caption.textAlignment = .center
        caption.adjustsFontSizeToFitWidth = true
        caption.minimumScaleFactor = 0.75
        caption.translatesAutoresizingMaskIntoConstraints = false
        addSubview(caption)

        bead.backgroundColor = Hide.ember
        bead.layer.cornerRadius = 3
        bead.isHidden = true
        bead.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bead)

        NSLayoutConstraint.activate([
            mark.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            mark.centerXAnchor.constraint(equalTo: centerXAnchor),
            mark.widthAnchor.constraint(equalToConstant: 26),
            mark.heightAnchor.constraint(equalToConstant: 26),
            caption.topAnchor.constraint(equalTo: mark.bottomAnchor, constant: 3),
            caption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            caption.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            bead.widthAnchor.constraint(equalToConstant: 6),
            bead.heightAnchor.constraint(equalToConstant: 6),
            bead.centerYAnchor.constraint(equalTo: mark.topAnchor, constant: 1),
            bead.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 1),
        ])
        redress()
    }

    required init?(coder: NSCoder) { nil }

    /// The dock is built before the core is awake, so the words are asked for
    /// again once there is something to read.
    func recaption() {
        caption.text = Vault.say(leaf)
    }

    private func redress() {
        // The carvings themselves carry the colour, so a dim tab is simply a
        // carving in shadow.
        mark.alpha = lit ? 1 : 0.42
        caption.textColor = lit ? Hide.gild : Hide.hush
    }
}

/// The bottom bar. Five halls, always reachable, never covering content.
final class Dock: UIView {
    static let height: CGFloat = 56

    private var tabs: [DockTab] = []
    private let hairline = UIView()
    var onPick: ((Int) -> Void)?

    init() {
        super.init(frame: .zero)
        backgroundColor = Hide.ink(14, 19, 15, 0.98)

        hairline.backgroundColor = Hide.brassDim.withAlphaComponent(0.5)
        hairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hairline)

        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        let plan: [(Int, UInt16)] = [
            (Canvas.aTempleDoors[2], Lexeme.tabDelve),
            (Canvas.bScarabBasic[1], Lexeme.tabHero),
            (Canvas.bSolarDevices[0], Lexeme.tabDaily),
            (Canvas.bAncientSymbols[0], Lexeme.tabAtlas),
            (Canvas.bTempleMechanisms[0], Lexeme.tabMore),
        ]
        for (index, leaf) in plan.enumerated() {
            let tab = DockTab(leaf.0, leaf.1)
            tab.addAction(UIAction { [weak self] _ in self?.onPick?(index) }, for: .touchUpInside)
            row.addArrangedSubview(tab)
            tabs.append(tab)
        }

        NSLayoutConstraint.activate([
            hairline.topAnchor.constraint(equalTo: topAnchor),
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.heightAnchor.constraint(equalToConstant: Dock.height),
        ])
        light(0)
    }

    required init?(coder: NSCoder) { nil }

    func relabel() {
        for tab in tabs { tab.recaption() }
    }

    func light(_ index: Int) {
        for (slot, tab) in tabs.enumerated() {
            tab.lit = slot == index
        }
    }

    /// A dot on the tabs that have something to collect.
    func flag(daily: Bool) {
        guard tabs.count > 2 else { return }
        tabs[2].waiting = daily
    }
}
