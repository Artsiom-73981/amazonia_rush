import UIKit

/// A carved panel. Every list row, card and dialog in the game sits on one.
final class Slab: UIView {
    enum Cast {
        case sunk
        case raised
        case lit
        case warn
    }

    private let sheen = CAGradientLayer()
    var cast: Cast = .sunk { didSet { redress() } }

    init(_ cast: Cast = .sunk, corner: CGFloat = Grid.corner) {
        self.cast = cast
        super.init(frame: .zero)
        layer.cornerRadius = corner
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        sheen.cornerRadius = corner
        sheen.startPoint = CGPoint(x: 0.1, y: 0)
        sheen.endPoint = CGPoint(x: 0.9, y: 1)
        layer.insertSublayer(sheen, at: 0)
        redress()
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        sheen.frame = bounds
    }

    private func redress() {
        switch cast {
        case .sunk:
            sheen.colors = [Hide.loam.cgColor, Hide.pitch.cgColor]
            layer.borderColor = Hide.ink(58, 70, 58).cgColor
        case .raised:
            sheen.colors = [Hide.plinth.cgColor, Hide.slate.cgColor]
            layer.borderColor = Hide.brassDim.cgColor
        case .lit:
            sheen.colors = [Hide.ink(72, 62, 36).cgColor, Hide.ink(42, 38, 24).cgColor]
            layer.borderColor = Hide.brass.cgColor
        case .warn:
            sheen.colors = [Hide.ink(70, 36, 38).cgColor, Hide.ink(38, 22, 24).cgColor]
            layer.borderColor = Hide.bruise.cgColor
        }
    }
}

/// The only button type in the game. Draws itself, speaks to the audio deck
/// and reports taps through a closure.
final class PressPad: UIControl {
    enum Build {
        case stone
        case gold
        case ghost
        case danger
    }

    private let shell = Slab(.raised)
    private let caption = UILabel()
    private let footnote = UILabel()
    private let glyph = UIImageView()
    private var touchedAt = Date.distantPast
    var onPress: (() -> Void)?
    var build: Build = .stone { didSet { refit() } }

    init(_ build: Build = .stone) {
        self.build = build
        super.init(frame: .zero)
        shell.isUserInteractionEnabled = false
        shell.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shell)

        caption.font = Scribe.carved(15)
        caption.textAlignment = .center
        caption.numberOfLines = 2
        caption.adjustsFontSizeToFitWidth = true
        caption.minimumScaleFactor = 0.7
        caption.translatesAutoresizingMaskIntoConstraints = false
        addSubview(caption)

        footnote.font = Scribe.plain(11)
        footnote.textAlignment = .center
        footnote.textColor = Hide.murmur
        footnote.translatesAutoresizingMaskIntoConstraints = false
        addSubview(footnote)

        glyph.contentMode = .scaleAspectFit
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)

        NSLayoutConstraint.activate([
            shell.topAnchor.constraint(equalTo: topAnchor),
            shell.leadingAnchor.constraint(equalTo: leadingAnchor),
            shell.trailingAnchor.constraint(equalTo: trailingAnchor),
            shell.bottomAnchor.constraint(equalTo: bottomAnchor),
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyph.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            glyph.widthAnchor.constraint(equalTo: glyph.heightAnchor),
            caption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            caption.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            footnote.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            footnote.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        ])

        glyphHeight = glyph.heightAnchor.constraint(equalToConstant: 0)
        glyphHeight.isActive = true
        captionCentre = caption.centerYAnchor.constraint(equalTo: centerYAnchor)
        captionCentre.isActive = true
        footnote.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: 1).isActive = true

        addTarget(self, action: #selector(pressDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(pressUp), for: [.touchUpOutside, .touchCancel, .touchDragExit])
        addTarget(self, action: #selector(pressFire), for: .touchUpInside)
        refit()
    }

    required init?(coder: NSCoder) { nil }

    private var glyphHeight: NSLayoutConstraint!
    private var captionCentre: NSLayoutConstraint!

    func dress(_ title: String, note: String? = nil, art: UIImage? = nil) {
        caption.text = title
        footnote.text = note
        footnote.isHidden = note == nil
        glyph.image = art
        let hasArt = art != nil
        glyphHeight.constant = hasArt ? 42 : 0
        captionCentre.constant = hasArt ? 24 : (note == nil ? 0 : -6)
        setNeedsLayout()
    }

    override var isEnabled: Bool { didSet { refit() } }

    private func refit() {
        let dull = !isEnabled
        switch build {
        case .stone:
            shell.cast = .raised
            caption.textColor = dull ? Hide.hush : Hide.parchment
        case .gold:
            shell.cast = .lit
            caption.textColor = dull ? Hide.hush : Hide.gild
        case .ghost:
            shell.cast = .sunk
            caption.textColor = dull ? Hide.hush : Hide.murmur
        case .danger:
            shell.cast = .warn
            caption.textColor = dull ? Hide.hush : Hide.ink(248, 196, 196)
        }
        alpha = dull ? 0.55 : 1
    }

    @objc private func pressDown() {
        touchedAt = Date()
        UIView.animate(withDuration: 0.08) {
            self.transform = CGAffineTransform(scaleX: 0.965, y: 0.965)
        }
    }

    @objc private func pressUp() {
        UIView.animate(withDuration: 0.14) { self.transform = .identity }
    }

    @objc private func pressFire() {
        pressUp()
        Deck.shared.cue(Canvas.buttonClickCue)
        Tremor.tap()
        onPress?()
    }
}

/// A meter that animates its fill rather than snapping, used for loading,
/// quotas, integrity and every progress row.
final class Meter: UIView {
    private let trough = CALayer()
    private let fill = CAGradientLayer()
    private let crest = CALayer()
    private var share: CGFloat = 0
    var warm = true { didSet { recolour() } }

    init(thickness: CGFloat = 10) {
        super.init(frame: .zero)
        heightAnchor.constraint(equalToConstant: thickness).isActive = true
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = thickness / 2
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        trough.backgroundColor = Hide.ink(16, 20, 17).cgColor
        layer.addSublayer(trough)
        fill.startPoint = CGPoint(x: 0, y: 0.5)
        fill.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(fill)
        crest.backgroundColor = UIColor.white.withAlphaComponent(0.35).cgColor
        layer.addSublayer(crest)
        recolour()
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        trough.frame = bounds
        reflow(animated: false)
    }

    private func recolour() {
        fill.colors = warm
            ? [Hide.brassDim.cgColor, Hide.gild.cgColor]
            : [Hide.ink(44, 92, 120).cgColor, Hide.lapis.cgColor]
    }

    func pour(_ value: Float, animated: Bool = true) {
        share = CGFloat(min(1, max(0, value)))
        reflow(animated: animated)
    }

    private func reflow(animated: Bool) {
        let width = bounds.width * share
        let target = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        let cap = CGRect(x: max(0, width - 2), y: 0, width: width > 2 ? 2 : 0, height: bounds.height)
        if animated {
            let glide = CABasicAnimation(keyPath: "bounds")
            glide.duration = 0.32
            glide.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fill.add(glide, forKey: nil)
        } else {
            fill.removeAllAnimations()
        }
        fill.frame = target
        crest.frame = cap
    }
}

/// The purse strip. Shown at the top of nearly every screen.
final class Hoard: UIView {
    private var dials: [UILabel] = []
    private var pips: [UIView] = []

    init() {
        super.init(frame: .zero)
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        let tints = [Hide.gild, Hide.lapis, Hide.verdure, Hide.violetDusk]
        for slot in 0..<4 {
            let cell = Slab(.sunk, corner: 9)
            let pip = UIView()
            pip.backgroundColor = tints[slot]
            pip.layer.cornerRadius = 4
            pip.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(pip)
            let dial = UILabel()
            dial.font = Scribe.tally(13)
            dial.textColor = Hide.parchment
            dial.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(dial)
            NSLayoutConstraint.activate([
                pip.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 7),
                pip.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                pip.widthAnchor.constraint(equalToConstant: 8),
                pip.heightAnchor.constraint(equalToConstant: 8),
                dial.leadingAnchor.constraint(equalTo: pip.trailingAnchor, constant: 5),
                dial.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
                dial.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            row.addArrangedSubview(cell)
            dials.append(dial)
            pips.append(pip)
        }
        heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    required init?(coder: NSCoder) { nil }

    func show(_ purse: Purse) {
        for slot in 0..<dials.count {
            let fresh = Digits.brief(purse.amount(at: slot))
            if dials[slot].text != fresh {
                dials[slot].text = fresh
                let beat = CABasicAnimation(keyPath: "transform.scale")
                beat.fromValue = 1.3
                beat.toValue = 1
                beat.duration = 0.24
                dials[slot].layer.add(beat, forKey: nil)
            }
        }
    }
}

/// Title bar with a back arrow drawn in code.
final class Crest: UIView {
    private let heading = UILabel()
    private let retreat = PressPad(.ghost)

    init(_ title: String, back: (() -> Void)?) {
        super.init(frame: .zero)
        heading.text = title
        heading.font = Scribe.carved(20, .bold)
        heading.textColor = Hide.gild
        heading.textAlignment = .center
        heading.translatesAutoresizingMaskIntoConstraints = false
        addSubview(heading)

        retreat.dress(Vault.say(Lexeme.navBack))
        retreat.onPress = back
        retreat.isHidden = back == nil
        retreat.translatesAutoresizingMaskIntoConstraints = false
        addSubview(retreat)

        NSLayoutConstraint.activate([
            heading.centerXAnchor.constraint(equalTo: centerXAnchor),
            heading.centerYAnchor.constraint(equalTo: centerYAnchor),
            heading.leadingAnchor.constraint(greaterThanOrEqualTo: retreat.trailingAnchor, constant: 8),
            retreat.leadingAnchor.constraint(equalTo: leadingAnchor),
            retreat.centerYAnchor.constraint(equalTo: centerYAnchor),
            retreat.widthAnchor.constraint(equalToConstant: 72),
            retreat.heightAnchor.constraint(equalToConstant: 34),
            heightAnchor.constraint(equalToConstant: 42),
        ])
    }

    required init?(coder: NSCoder) { nil }
}

/// Horizontal tab strip used by the meta screens.
final class Rail: UIView {
    private var pads: [PressPad] = []
    private let marker = UIView()
    private var picked = 0
    var onPick: ((Int) -> Void)?

    init(_ titles: [String]) {
        super.init(frame: .zero)
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.spacing = 4
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 36),
        ])
        for (index, title) in titles.enumerated() {
            let pad = PressPad(index == 0 ? .gold : .ghost)
            pad.dress(title)
            pad.onPress = { [weak self] in self?.pick(index) }
            row.addArrangedSubview(pad)
            pads.append(pad)
        }
    }

    required init?(coder: NSCoder) { nil }

    func pick(_ index: Int) {
        guard pads.indices.contains(index) else { return }
        picked = index
        for (slot, pad) in pads.enumerated() {
            pad.build = slot == index ? .gold : .ghost
        }
        onPick?(index)
    }
}

/// Short-lived banner used for refusals, gains and hints.
final class Murmur {
    static func drift(_ text: String, over host: UIView, kind: Slab.Cast = .raised) {
        let card = Slab(kind)
        card.alpha = 0
        card.translatesAutoresizingMaskIntoConstraints = false
        let line = UILabel()
        line.text = text
        line.font = Scribe.plain(13, .medium)
        line.textColor = Hide.parchment
        line.numberOfLines = 3
        line.textAlignment = .center
        line.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(line)
        host.addSubview(card)
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: card.topAnchor, constant: 9),
            line.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            line.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            line.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -9),
            card.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            card.widthAnchor.constraint(lessThanOrEqualTo: host.widthAnchor, multiplier: 0.86),
            card.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -84),
        ])
        host.layoutIfNeeded()
        card.transform = CGAffineTransform(translationX: 0, y: 18)
        UIView.animate(withDuration: 0.22) {
            card.alpha = 1
            card.transform = .identity
        }
        UIView.animate(withDuration: 0.3, delay: 1.7, options: []) {
            card.alpha = 0
            card.transform = CGAffineTransform(translationX: 0, y: -12)
        } completion: { _ in
            card.removeFromSuperview()
        }
    }
}

extension UIView {
    func pin(into host: UIView, inset: CGFloat = 0) {
        translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(self)
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: host.topAnchor, constant: inset),
            leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: inset),
            trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -inset),
            bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -inset),
        ])
    }

    @discardableResult
    func measure(_ width: CGFloat? = nil, _ height: CGFloat? = nil) -> Self {
        translatesAutoresizingMaskIntoConstraints = false
        if let width { widthAnchor.constraint(equalToConstant: width).isActive = true }
        if let height { heightAnchor.constraint(equalToConstant: height).isActive = true }
        return self
    }
}

/// Builds a plain label in one line of calling code.
func chisel(
    _ text: String,
    _ font: UIFont = Scribe.plain(13),
    _ tint: UIColor = Hide.parchment,
    lines: Int = 1,
    align: NSTextAlignment = .left
) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = font
    label.textColor = tint
    label.numberOfLines = lines
    label.textAlignment = align
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}
