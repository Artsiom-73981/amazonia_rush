import UIKit

/// The Spirit Lattice: four branches of permanent upgrades.
final class LatticeStage: ScrollStage {
    override var titleLexeme: UInt16? { Lexeme.latticeTitle }
    override var sceneWish: Int? { Canvas.bBgObservatoryScene }

    private var branchPicked = 0
    private var rail: Rail?

    override func awaken() {
        var scroll = Oracle.shared.ask(Rite.lattice)
        paint(LatticeView(&scroll))
    }

    private func paint(_ sheet: LatticeView) {
        hoard.show(sheet.purse)
        clear()

        if rail == nil, !sheet.branches.isEmpty {
            let strip = Rail(sheet.branches.map { Vault.say($0.0) })
            strip.onPick = { [weak self] slot in
                self?.branchPicked = slot
                self?.awaken()
            }
            rail = strip
        }
        if let strip = rail {
            add(strip)
        }

        let tally = chisel(
            Vault.say(Lexeme.navTotal) + "  " + "\(sheet.ranks)" + " / " + "\(sheet.rankCap)",
            Scribe.tally(12), Hide.murmur, align: .center
        )
        tally.textAlignment = .center
        add(tally)

        if sheet.branches.indices.contains(branchPicked) {
            add(banner(Vault.say(sheet.branches[branchPicked].1), Hide.hush))
        }

        for (index, node) in sheet.nodes.enumerated() where Int(node.branch) == branchPicked {
            let deedTitle: String
            if node.maxed {
                deedTitle = Vault.say(Lexeme.navMax)
            } else if !node.unlocked {
                deedTitle = Vault.say(Lexeme.navLevel) + " \(node.attunement)"
            } else {
                deedTitle = Vault.say(Lexeme.navBuy)
            }
            add(Ledge(
                title: Vault.say(node.name),
                blurb: Vault.say(node.blurb),
                tailTop: "\(node.rank)" + " / " + "\(node.ceiling)",
                tailLow: node.maxed ? nil : Toll.of(shards: node.shards, cores: node.cores),
                share: Float(node.rank) / Float(node.ceiling),
                cast: node.maxed ? .lit : (node.unlocked ? .raised : .sunk),
                deed: deedTitle,
                deedBuild: node.affordable ? .gold : .ghost,
                deedLive: node.affordable,
                fire: { [weak self] in self?.buy(index) }
            ))
        }
    }

    private func buy(_ node: Int) {
        var quill = Quill()
        quill.quad(UInt32(node))
        var scroll = Oracle.shared.ask(Rite.latticeBuy, quill.bytes)
        let done = scroll.flag()
        let sheet = LatticeView(&scroll)
        if done {
            Oracle.shared.preserve()
            Deck.shared.cue(Canvas.unlockCue, gain: 0.8)
            Tremor.thud()
        } else {
            whisper(Vault.say(Lexeme.navLocked), sour: true)
        }
        paint(sheet)
    }
}

/// The Scarab Cadre: recruit, rank up, seat on the bench and bind powers.
final class CadreStage: ScrollStage {
    override var titleLexeme: UInt16? { Lexeme.cadreTitle }
    override var sceneWish: Int? { Canvas.bBgUndergroundTempleScene }

    private var holding: Int?
    private var powerHolding: Int?

    override func awaken() {
        var scroll = Oracle.shared.ask(Rite.cadre)
        paint(CadreView(&scroll))
    }

    private func paint(_ sheet: CadreView) {
        hoard.show(sheet.purse)
        clear()

        add(banner(Vault.say(Lexeme.uiBenchTitle)))
        let benchRow = UIStackView()
        benchRow.axis = .horizontal
        benchRow.distribution = .fillEqually
        benchRow.spacing = 6
        for (seat, held) in sheet.bench.enumerated() {
            let pad = PressPad(held >= 0 ? .gold : .ghost)
            let index = Int(held)
            let title = held >= 0 && sheet.scarabs.indices.contains(index)
                ? Vault.say(sheet.scarabs[index].name)
                : Vault.say(Lexeme.navEmpty)
            pad.dress(title, note: "\(seat + 1)")
            pad.onPress = { [weak self] in self?.seat(seat, sheet) }
            pad.heightAnchor.constraint(equalToConstant: 64).isActive = true
            benchRow.addArrangedSubview(pad)
        }
        add(benchRow)

        if let picked = holding, sheet.scarabs.indices.contains(picked) {
            add(banner(Vault.say(Lexeme.uiBenchAsk), Hide.gild))
        }

        add(banner(Vault.say(Lexeme.cadreTitle)))
        for (index, scarab) in sheet.scarabs.enumerated() {
            let asleep = !scarab.awake
            let deedTitle: String
            if asleep {
                deedTitle = Vault.say(Lexeme.mapRegion) + " \(scarab.wakesAt + 1)"
            } else if scarab.rank >= scarab.ceiling {
                deedTitle = Vault.say(Lexeme.navMax)
            } else {
                deedTitle = Vault.say(Lexeme.cadreFeed)
            }
            add(Ledge(
                title: Vault.say(scarab.name),
                blurb: asleep ? Vault.say(Lexeme.cadreSealed) : Vault.say(scarab.traitLine),
                tailTop: asleep ? nil : "\(scarab.rank)" + " / " + "\(scarab.ceiling)",
                tailLow: asleep || scarab.rank >= scarab.ceiling
                    ? nil
                    : Toll.of(shards: scarab.feed, resin: scarab.resin),
                share: asleep ? nil : Float(scarab.rank) / Float(scarab.ceiling),
                art: Vault.prop(CadreStage.portrait(index)),
                cast: scarab.seat >= 0 ? .lit : (asleep ? .sunk : .raised),
                deed: deedTitle,
                deedBuild: scarab.canRank ? .gold : .ghost,
                deedLive: scarab.canRank,
                deedWide: 100,
                fire: { [weak self] in self?.feed(index) }
            ))
            if !asleep {
                let hold = PressPad(holding == index ? .gold : .ghost)
                hold.dress(scarab.seat >= 0 ? Vault.say(Lexeme.navUnequip) : Vault.say(Lexeme.navEquip))
                hold.onPress = { [weak self] in self?.grasp(index, scarab) }
                hold.heightAnchor.constraint(equalToConstant: 34).isActive = true
                add(hold)
            }
        }

        add(banner(Vault.say(Lexeme.homePowerLabel)))
        let seatRow = UIStackView()
        seatRow.axis = .horizontal
        seatRow.distribution = .fillEqually
        seatRow.spacing = 6
        for (seat, bound) in sheet.powerSeats.enumerated() {
            let pad = PressPad(bound >= 0 ? .gold : .ghost)
            let index = Int(bound)
            pad.dress(
                bound >= 0 && sheet.powers.indices.contains(index)
                    ? Vault.say(sheet.powers[index].name)
                    : Vault.say(Lexeme.navEmpty),
                note: "\(seat + 1)"
            )
            pad.onPress = { [weak self] in self?.bind(seat) }
            pad.heightAnchor.constraint(equalToConstant: 60).isActive = true
            seatRow.addArrangedSubview(pad)
        }
        add(seatRow)

        for (index, power) in sheet.powers.enumerated() {
            add(Ledge(
                title: Vault.say(power.name),
                blurb: Vault.say(power.blurb),
                tailTop: Vault.say(Lexeme.powerRest) + " \(power.rest)",
                cast: powerHolding == index ? .lit : (power.unlocked ? .raised : .sunk),
                deed: power.unlocked ? Vault.say(Lexeme.navEquip) : Vault.say(Lexeme.navLocked),
                deedBuild: powerHolding == index ? .gold : .stone,
                deedLive: power.unlocked,
                fire: { [weak self] in
                    self?.powerHolding = self?.powerHolding == index ? nil : index
                    self?.awaken()
                }
            ))
        }
    }

    private static func portrait(_ index: Int) -> Int {
        let pool = index % 2 == 0 ? Canvas.bScarabBasic : Canvas.bScarabSupport
        return pool[(index / 2) % pool.count]
    }

    private func feed(_ index: Int) {
        var quill = Quill()
        quill.quad(UInt32(index))
        var scroll = Oracle.shared.ask(Rite.scarabRank, quill.bytes)
        let done = scroll.flag()
        let sheet = CadreView(&scroll)
        if done {
            Oracle.shared.preserve()
            Deck.shared.cue(Canvas.confirmationCue, gain: 0.8)
        } else {
            whisper(Vault.say(Lexeme.navLocked), sour: true)
        }
        paint(sheet)
    }

    private func grasp(_ index: Int, _ scarab: ScarabView) {
        if scarab.seat >= 0 {
            send(scarab: -1, seat: Int(scarab.seat))
            holding = nil
        } else {
            holding = holding == index ? nil : index
            awaken()
        }
    }

    private func seat(_ slot: Int, _ sheet: CadreView) {
        guard let picked = holding else {
            if sheet.bench.indices.contains(slot), sheet.bench[slot] >= 0 {
                send(scarab: -1, seat: slot)
            } else {
                whisper(Vault.say(Lexeme.uiBenchAsk))
            }
            return
        }
        holding = nil
        send(scarab: Int32(picked), seat: slot)
    }

    private func send(scarab: Int32, seat: Int) {
        var quill = Quill()
        quill.signed(scarab)
        quill.quad(UInt32(seat))
        var scroll = Oracle.shared.ask(Rite.scarabDeploy, quill.bytes)
        let done = scroll.flag()
        let sheet = CadreView(&scroll)
        if done {
            Oracle.shared.preserve()
            Deck.shared.cue(Canvas.tabSwitchCue, gain: 0.6)
        }
        paint(sheet)
    }

    private func bind(_ seat: Int) {
        var quill = Quill()
        quill.signed(powerHolding.map { Int32($0) } ?? -1)
        quill.quad(UInt32(seat))
        var scroll = Oracle.shared.ask(Rite.powerAssign, quill.bytes)
        let done = scroll.flag()
        let sheet = CadreView(&scroll)
        if done {
            powerHolding = nil
            Oracle.shared.preserve()
            Deck.shared.cue(Canvas.confirmCue, gain: 0.7)
        } else {
            whisper(Vault.say(Lexeme.navLocked), sour: true)
        }
        paint(sheet)
    }
}

/// The Reliquary: sixteen relics in four sets, each set granting a bonus.
final class ReliquaryStage: ScrollStage {
    override var titleLexeme: UInt16? { Lexeme.relicTitle }
    override var sceneWish: Int? { Canvas.bBgOasisShrineScene }

    override func awaken() {
        var scroll = Oracle.shared.ask(Rite.relics)
        let sheet = ReliquaryView(&scroll)
        hoard.show(sheet.purse)
        clear()

        add(banner(Vault.say(Lexeme.uiRelicSets)))
        for cluster in sheet.clusters {
            add(Ledge(
                title: Vault.say(cluster.name),
                blurb: Vault.say(cluster.blurb),
                tailTop: "\(cluster.held)" + " / " + "\(cluster.total)",
                share: Float(cluster.held) / Float(cluster.total),
                cast: cluster.complete ? .lit : .sunk
            ))
        }

        add(banner(Vault.say(Lexeme.relicTitle)))
        for (index, relic) in sheet.relics.enumerated() {
            add(Ledge(
                title: relic.held ? Vault.say(relic.name) : Vault.say(Lexeme.navLocked),
                blurb: Vault.say(relic.homeName),
                tailTop: relic.held ? Vault.say(Lexeme.navOwned) : nil,
                art: relic.held ? Vault.prop(Canvas.aAncientRelics[index % 4]) : nil,
                cast: relic.held ? .raised : .sunk
            ))
        }
    }
}

/// The Resin Forge: spend resin on run-long charms.
final class ForgeStage: ScrollStage {
    override var titleLexeme: UInt16? { Lexeme.forgeTitle }
    override var sceneWish: Int? { Canvas.bBgUndergroundMechanismComplexScene }

    override func awaken() {
        var scroll = Oracle.shared.ask(Rite.forge)
        paint(ForgeView(&scroll))
    }

    private func paint(_ sheet: ForgeView) {
        hoard.show(sheet.purse)
        clear()
        add(banner(Vault.say(Lexeme.forgeTitle)))
        add(chisel(Vault.say(Lexeme.forgeBlurb), Scribe.plain(12), Hide.murmur, lines: 0))
        for (index, recipe) in sheet.recipes.enumerated() {
            add(Ledge(
                title: Vault.say(recipe.name),
                blurb: Vault.say(recipe.blurb),
                tailTop: "x" + "\(recipe.made)",
                tailLow: Toll.of(shards: UInt64(recipe.shardToll), resin: UInt64(recipe.resinToll)),
                art: Vault.prop(Canvas.bTempleMechanisms[index % 4]),
                cast: recipe.made > 0 ? .raised : .sunk,
                deed: Vault.say(Lexeme.navCraft),
                deedBuild: recipe.canMake ? .gold : .ghost,
                deedLive: recipe.canMake,
                fire: { [weak self] in self?.make(index) }
            ))
        }
    }

    private func make(_ index: Int) {
        var quill = Quill()
        quill.quad(UInt32(index))
        var scroll = Oracle.shared.ask(Rite.forgeMake, quill.bytes)
        let done = scroll.flag()
        let sheet = ForgeView(&scroll)
        if done {
            Oracle.shared.preserve()
            Deck.shared.cue(Canvas.ancientMechanismActivatedCue, gain: 0.8)
            Tremor.thud()
        } else {
            whisper(Vault.say(Lexeme.navLocked), sour: true)
        }
        paint(sheet)
    }
}

/// The Caravan: four offers that rotate at dawn, plus the board skins.
final class CaravanStage: ScrollStage {
    override var titleLexeme: UInt16? { Lexeme.caravanTitle }
    override var sceneWish: Int? { Canvas.bBgAncientCityHallScene }

    override func awaken() {
        var scroll = Oracle.shared.ask(Rite.caravan)
        paint(CaravanView(&scroll))
    }

    private func paint(_ sheet: CaravanView) {
        hoard.show(sheet.purse)
        clear()
        add(banner(Vault.say(Lexeme.caravanTitle)))
        add(chisel(
            Vault.say(Lexeme.caravanRefresh) + "  " + Digits.clockFace(sheet.untilDawn),
            Scribe.plain(12), Hide.murmur
        ))

        for (slot, offer) in sheet.offers.enumerated() {
            let gain = Digits.brief(UInt64(offer.getAmount)) + " " + Toll.purseName(offer.getPurse)
            let cost = Digits.brief(UInt64(offer.payAmount)) + " " + Toll.purseName(offer.payPurse)
            add(Ledge(
                title: Vault.say(offer.name),
                blurb: Vault.say(offer.blurb),
                tailTop: gain,
                tailLow: cost,
                art: Vault.prop(Canvas.aTreasureChests[slot % 4]),
                cast: offer.taken ? .sunk : .raised,
                deed: offer.taken ? Vault.say(Lexeme.navClaimed) : Vault.say(Lexeme.navBuy),
                deedBuild: offer.affordable && !offer.taken ? .gold : .ghost,
                deedLive: offer.affordable && !offer.taken,
                fire: { [weak self] in self?.trade(slot) }
            ))
        }

        add(banner(Vault.say(Lexeme.uiSkins)))
        let skinRow = UIStackView()
        skinRow.axis = .horizontal
        skinRow.distribution = .fillEqually
        skinRow.spacing = 6
        for skin in 0..<6 {
            let owned = sheet.skins & (1 << UInt32(skin)) != 0
            let worn = sheet.skinWorn == UInt32(skin)
            let pad = PressPad(worn ? .gold : (owned ? .stone : .ghost))
            pad.dress(
                "\(skin + 1)",
                note: worn
                    ? Vault.say(Lexeme.navEquipped)
                    : (owned ? Vault.say(Lexeme.navOwned) : Vault.say(Lexeme.navLocked))
            )
            pad.isEnabled = owned
            pad.onPress = { [weak self] in self?.wear(skin) }
            pad.heightAnchor.constraint(equalToConstant: 58).isActive = true
            skinRow.addArrangedSubview(pad)
        }
        add(skinRow)
    }

    private func trade(_ slot: Int) {
        var quill = Quill()
        quill.quad(UInt32(slot))
        var scroll = Oracle.shared.ask(Rite.caravanTrade, quill.bytes)
        let done = scroll.flag()
        let sheet = CaravanView(&scroll)
        if done {
            Oracle.shared.preserve()
            Deck.shared.cue(Canvas.rewardCue, gain: 0.85)
            Tremor.cheer()
        } else {
            whisper(Vault.say(Lexeme.navLocked), sour: true)
        }
        paint(sheet)
    }

    private func wear(_ skin: Int) {
        var quill = Quill()
        quill.quad(UInt32(skin))
        var scroll = Oracle.shared.ask(Rite.skinWear, quill.bytes)
        _ = scroll.flag()
        let sheet = CaravanView(&scroll)
        Oracle.shared.preserve()
        Deck.shared.cue(Canvas.toggleOffCue, gain: 0.6)
        paint(sheet)
    }
}
