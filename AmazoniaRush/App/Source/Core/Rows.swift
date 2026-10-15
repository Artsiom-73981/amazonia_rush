import UIKit

/// Description of one list row. The meta screens are all built from these, so
/// they stay consistent without a single table view.
struct Ledge {
    var title: String
    var blurb: String?
    var tailTop: String?
    var tailLow: String?
    var share: Float?
    var coolShare = false
    var art: UIImage?
    var cast: Slab.Cast = .sunk
    var deed: String?
    var deedBuild: PressPad.Build = .stone
    var deedLive = true
    var deedWide: CGFloat = 92
    var fire: (() -> Void)?
}

/// Builds the row view. Returns a plain view so callers can drop it straight
/// into a stack.
func carve(_ ledge: Ledge) -> UIView {
    let card = Slab(ledge.cast)

    let heading = chisel(ledge.title, Scribe.carved(15), Hide.parchment, lines: 2)
    let column = UIStackView(arrangedSubviews: [heading])
    column.axis = .vertical
    column.spacing = 3

    if let blurb = ledge.blurb, !blurb.isEmpty {
        column.addArrangedSubview(chisel(blurb, Scribe.plain(11), Hide.murmur, lines: 0))
    }
    if let share = ledge.share {
        let bar = Meter(thickness: 6)
        bar.warm = !ledge.coolShare
        bar.pour(share, animated: false)
        column.addArrangedSubview(bar)
    }

    let middle = UIStackView(arrangedSubviews: [column])
    middle.axis = .horizontal
    middle.spacing = 10
    middle.alignment = .center

    if let art = ledge.art {
        let badge = UIImageView(image: art)
        badge.contentMode = .scaleAspectFit
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.widthAnchor.constraint(equalToConstant: 42).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 42).isActive = true
        middle.insertArrangedSubview(badge, at: 0)
    }

    if ledge.tailTop != nil || ledge.tailLow != nil {
        let top = chisel(ledge.tailTop ?? "", Scribe.tally(13), Hide.gild, align: .right)
        let low = chisel(ledge.tailLow ?? "", Scribe.plain(10), Hide.hush, align: .right)
        let tail = UIStackView(arrangedSubviews: [top, low])
        tail.axis = .vertical
        tail.spacing = 1
        tail.translatesAutoresizingMaskIntoConstraints = false
        tail.setContentHuggingPriority(.required, for: .horizontal)
        middle.addArrangedSubview(tail)
    }

    if let deed = ledge.deed {
        let pad = PressPad(ledge.deedBuild)
        pad.dress(deed)
        pad.isEnabled = ledge.deedLive
        pad.onPress = ledge.fire
        pad.translatesAutoresizingMaskIntoConstraints = false
        pad.widthAnchor.constraint(equalToConstant: ledge.deedWide).isActive = true
        pad.heightAnchor.constraint(equalToConstant: 40).isActive = true
        middle.addArrangedSubview(pad)
    }

    middle.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(middle)
    NSLayoutConstraint.activate([
        middle.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
        middle.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
        middle.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
        middle.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
    ])
    return card
}

/// A small headline used to break long lists into sections.
func banner(_ text: String, _ tint: UIColor = Hide.brass) -> UIView {
    let line = chisel(text.uppercased(), Scribe.carved(12, .bold), tint)
    line.setContentHuggingPriority(.required, for: .vertical)
    let wrap = UIView()
    line.translatesAutoresizingMaskIntoConstraints = false
    wrap.addSubview(line)
    NSLayoutConstraint.activate([
        line.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 8),
        line.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 2),
        line.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
        line.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -2),
    ])
    return wrap
}

/// Common scaffolding for the data-driven meta screens: a scroller that is
/// cleared and refilled on every appearance.
class ScrollStage: Stage {
    private(set) var column: UIStackView!

    override func assemble() {
        let (_, stack) = makeScroller()
        column = stack
    }

    func clear() {
        for spare in column.arrangedSubviews {
            column.removeArrangedSubview(spare)
            spare.removeFromSuperview()
        }
    }

    func add(_ view: UIView) {
        column.addArrangedSubview(view)
    }

    func add(_ ledge: Ledge) {
        column.addArrangedSubview(carve(ledge))
    }
}

/// Price phrasing shared by every shop row.
enum Toll {
    static func of(shards: UInt64, cores: UInt64 = 0, resin: UInt64 = 0) -> String {
        var parts: [String] = []
        let coins = Lexeme.coinNameAll
        if shards > 0 { parts.append(Digits.brief(shards) + " " + Vault.say(coins[0])) }
        if cores > 0 { parts.append(Digits.brief(cores) + " " + Vault.say(coins[1])) }
        if resin > 0 { parts.append(Digits.brief(resin) + " " + Vault.say(coins[2])) }
        return parts.isEmpty ? Vault.say(Lexeme.navFree) : parts.joined(separator: "  ")
    }

    static func purseName(_ slot: UInt32) -> String {
        let coins = Lexeme.coinNameAll
        let index = Int(slot)
        return coins.indices.contains(index) ? Vault.say(coins[index]) : ""
    }
}
