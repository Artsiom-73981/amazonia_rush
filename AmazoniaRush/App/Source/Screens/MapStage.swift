import SpriteKit
import UIKit

/// The desert above the temple. The player walks the scarab across the sand;
/// standing on a dig site offers it, and opening it lists its halls.
final class MapStage: Stage {
    override var titleLexeme: UInt16? { Lexeme.mapTitle }

    private let sands = SKView()
    private let outland = OutlandCanvas(size: CGSize(width: 360, height: 560))
    private let hint = chisel("", Scribe.plain(11), Hide.murmur, lines: 2, align: .center)

    private let banner = Slab(.lit)
    private let bannerName = chisel("", Scribe.carved(16, .bold), Hide.gild)
    private let bannerNote = chisel("", Scribe.plain(11), Hide.murmur)
    private let bannerPad = PressPad(.gold)

    private let card = Slab(.raised)
    private let siteName = chisel("", Scribe.carved(17, .bold), Hide.gild)
    private let siteBlurb = chisel("", Scribe.plain(12), Hide.murmur, lines: 2)
    private let siteScore = chisel("", Scribe.tally(12), Hide.parchment, align: .right)
    private let hallGrid = UIStackView()
    private let shutPad = PressPad(.ghost)

    private var atlas: MapView?
    private var standing: Int?

    // --- building ----------------------------------------------------------

    override func assemble() {
        sands.backgroundColor = .clear
        sands.allowsTransparency = true
        sands.pin(into: canvas)
        outland.onReach = { [weak self] site in self?.arrive(site) }
        sands.presentScene(outland)

        hint.text = Vault.say(Lexeme.mapWalk)
        let hintShell = Slab(.sunk, corner: 10)
        hintShell.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(hintShell)
        hint.pin(into: hintShell, inset: Grid.tight)

        // The offer: one line that never hides the sand the player is crossing.
        bannerPad.dress(Vault.say(Lexeme.mapEnter))
        bannerPad.onPress = { [weak self] in self?.unfold(true) }
        _ = bannerPad.measure(104, Grid.touch - 4)
        let bannerText = UIStackView(arrangedSubviews: [bannerName, bannerNote])
        bannerText.axis = .vertical
        bannerText.spacing = 1
        let bannerRow = UIStackView(arrangedSubviews: [bannerText, bannerPad])
        bannerRow.axis = .horizontal
        bannerRow.spacing = Grid.gap
        bannerRow.alignment = .center
        bannerRow.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(bannerRow)
        banner.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(banner)

        hallGrid.axis = .vertical
        hallGrid.spacing = Grid.tight

        let heading = UIStackView(arrangedSubviews: [siteName, siteScore])
        heading.axis = .horizontal
        heading.spacing = Grid.gap
        heading.alignment = .center
        siteScore.setContentHuggingPriority(.required, for: .horizontal)

        shutPad.dress(Vault.say(Lexeme.navClose))
        shutPad.onPress = { [weak self] in self?.unfold(false) }
        _ = shutPad.measure(nil, Grid.touch - 4)

        let column = UIStackView(arrangedSubviews: [heading, siteBlurb, hallGrid, shutPad])
        column.axis = .vertical
        column.spacing = Grid.tight
        column.setCustomSpacing(Grid.gap, after: siteBlurb)
        column.setCustomSpacing(Grid.gap, after: hallGrid)
        column.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(column)
        card.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(card)

        banner.alpha = 0
        card.alpha = 0
        NSLayoutConstraint.activate([
            hintShell.topAnchor.constraint(equalTo: canvas.topAnchor, constant: Grid.tight),
            hintShell.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: Grid.gutter),
            hintShell.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -Grid.gutter),

            bannerRow.topAnchor.constraint(equalTo: banner.topAnchor, constant: Grid.tight + 1),
            bannerRow.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: Grid.inset),
            bannerRow.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -Grid.inset),
            bannerRow.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -Grid.tight - 1),
            banner.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: Grid.gutter),
            banner.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -Grid.gutter),
            banner.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -Grid.gap),

            card.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: Grid.gutter),
            card.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -Grid.gutter),
            card.bottomAnchor.constraint(equalTo: canvas.bottomAnchor, constant: -Grid.gap),

            column.topAnchor.constraint(equalTo: card.topAnchor, constant: Grid.inset - 2),
            column.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Grid.inset),
            column.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Grid.inset),
            column.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Grid.inset),
        ])
    }

    override func awaken() {
        var scroll = Oracle.shared.ask(Rite.map)
        let fresh = MapView(&scroll)
        atlas = fresh
        hoard.show(fresh.purse)
        // The scarab starts where the digging stopped: the deepest open site.
        outland.settle(fresh, standingAt: fresh.regions.lastIndex(where: { $0.open }) ?? 0)
    }

    // --- standing on a site ------------------------------------------------

    private func arrive(_ site: Int?) {
        guard let atlas else { return }
        guard let site, atlas.regions.indices.contains(site) else {
            standing = nil
            fade(banner, in: false)
            fade(card, in: false)
            return
        }
        let fresh = standing != site
        standing = site
        let region = atlas.regions[site]
        bannerName.text = Vault.say(region.name)
        bannerNote.text = region.open
            ? Vault.say(Lexeme.mapCleared)
                .replacingOccurrences(of: "%1", with: "\(region.cleared)")
                .replacingOccurrences(of: "%2", with: "\(region.nodeSpan)")
            : Vault.say(Lexeme.navLocked)
        bannerPad.isEnabled = region.open
        if fresh {
            Deck.shared.cue(region.open ? Canvas.newAreaDiscoveredCue : Canvas.errorCue, gain: 0.5)
        }
        fade(card, in: false)
        fade(banner, in: true)
    }

    /// Swaps the one-line offer for the full list of halls.
    private func unfold(_ wanted: Bool) {
        guard let atlas, let site = standing, atlas.regions.indices.contains(site) else { return }
        let region = atlas.regions[site]
        if wanted {
            siteName.text = Vault.say(region.name)
            siteBlurb.text = region.open
                ? Vault.say(region.blurb)
                : Vault.say(Lexeme.mapSiteLocked)
            siteScore.text = "\(region.cleared) / \(region.nodeSpan)"
            dressHalls(region, site)
            Deck.shared.cue(Canvas.worldMapOpenCue, gain: 0.6)
        }
        fade(banner, in: !wanted)
        fade(card, in: wanted)
    }

    private func dressHalls(_ region: MapRegionView, _ site: Int) {
        for spare in hallGrid.arrangedSubviews {
            hallGrid.removeArrangedSubview(spare)
            spare.removeFromSuperview()
        }
        guard region.open else { return }
        var lane: UIStackView?
        for (slot, node) in region.nodes.enumerated() {
            if slot % 4 == 0 {
                let fresh = UIStackView()
                fresh.axis = .horizontal
                fresh.distribution = .fillEqually
                fresh.spacing = Grid.tight
                hallGrid.addArrangedSubview(fresh)
                lane = fresh
            }
            lane?.addArrangedSubview(chip(site, slot, node))
        }
    }

    private func chip(_ site: Int, _ slot: Int, _ node: MapNodeView) -> UIView {
        let pad = PressPad(node.keystone ? .gold : (node.open ? .stone : .ghost))
        let seals = String(repeating: "\u{2726}", count: Int(node.seals))
        pad.dress(
            node.open ? "\(slot + 1)" : "\u{2022}",
            note: node.open && !seals.isEmpty ? seals : nil
        )
        pad.isEnabled = node.open
        _ = pad.measure(nil, 42)
        pad.onPress = { [weak self] in self?.enter(site, slot) }
        return pad
    }

    private func fade(_ panel: UIView, in wanted: Bool) {
        guard (panel.alpha > 0.5) != wanted else { return }
        canvas.layoutIfNeeded()
        let drop = panel.bounds.height + Grid.gap
        if wanted { panel.transform = CGAffineTransform(translationX: 0, y: drop) }
        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseOut) {
            panel.alpha = wanted ? 1 : 0
            panel.transform = wanted ? .identity : CGAffineTransform(translationX: 0, y: drop)
        }
    }

    private func enter(_ region: Int, _ node: Int) {
        var quill = Quill()
        quill.quad(UInt32(region))
        quill.quad(UInt32(node))
        let (allowed, _) = Oracle.shared.descend(Rite.delveOpen, quill.bytes)
        guard allowed else {
            whisper(Vault.say(Lexeme.mapLockedNode), sour: true)
            return
        }
        Oracle.shared.preserve()
        Deck.shared.cue(Canvas.newAreaDiscoveredCue, gain: 0.7)
        // The chapter card first: a descent should read as a place you are
        // walking into, not as a level that loaded.
        Saga.shared.open(chapter: region) {
            Director.shared.go(DelveStage())
        }
    }

#if DEBUG
    func rehearse(_ site: Int) {
        outland.rehearse(site)
    }
#endif
}
