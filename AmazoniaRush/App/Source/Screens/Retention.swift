import UIKit

/// Dawn Rites: a seven-day cycle that pays more the longer the streak holds.
final class RitesStage: ScrollStage {
    override var titleLexeme: UInt16? { Lexeme.riteTitle }
    override var sceneWish: Int? { Canvas.aBgRoom3Scene }

    override func awaken() {
        var scroll = Oracle.shared.ask(Rite.rites)
        paint(RitesView(&scroll))
    }

    private func paint(_ sheet: RitesView) {
        hoard.show(sheet.purse)
        clear()

        add(chisel(Vault.say(Lexeme.riteBlurb), Scribe.plain(12), Hide.murmur, lines: 0))
        add(Ledge(
            title: Vault.say(Lexeme.riteStreak) + "  " + "\(sheet.streak)",
            blurb: sheet.ready
                ? Vault.say(Lexeme.riteDay) + " " + "\(sheet.slot + 1)"
                : Vault.say(Lexeme.riteNext) + "  " + Digits.clockFace(sheet.untilDawn),
            tailTop: Digits.brief(sheet.claimsEver),
            tailLow: Vault.say(Lexeme.navTotal),
            cast: sheet.ready ? .lit : .sunk,
            deed: sheet.ready ? Vault.say(Lexeme.navClaim) : Vault.say(Lexeme.navSoon),
            deedBuild: sheet.ready ? .gold : .ghost,
            deedLive: sheet.ready,
            fire: { [weak self] in self?.collect() }
        ))
        add(chisel(Vault.say(Lexeme.riteOffline), Scribe.plain(11), Hide.hush, lines: 0))

        add(banner(Vault.say(Lexeme.uiRiteWeek)))
        let coins = Lexeme.coinNameAll
        for (day, prize) in sheet.days.enumerated() {
            var parts: [String] = []
            if prize.shards > 0 { parts.append(Digits.brief(prize.shards) + " " + Vault.say(coins[0])) }
            if prize.cores > 0 { parts.append(Digits.brief(prize.cores) + " " + Vault.say(coins[1])) }
            if prize.resin > 0 { parts.append(Digits.brief(prize.resin) + " " + Vault.say(coins[2])) }
            if prize.extra > 0 { parts.append(Digits.brief(prize.extra) + " " + Vault.say(coins[3])) }
            add(Ledge(
                title: Vault.say(Lexeme.riteDay) + " " + "\(day + 1)",
                blurb: parts.joined(separator: "  "),
                tailTop: prize.today ? Vault.say(Lexeme.navNext) : nil,
                art: Vault.prop(Canvas.aCeremonialVessels[day % 4]),
                cast: prize.today ? .lit : .sunk
            ))
        }
    }

    private func collect() {
        var scroll = Oracle.shared.ask(Rite.riteClaim)
        let shards = scroll.quad()
        let cores = scroll.quad()
        let resin = scroll.quad()
        let seals = scroll.quad()
        let sheet = RitesView(&scroll)
        if shards + cores + resin + seals > 0 {
            Oracle.shared.preserve()
            Deck.shared.cue(Canvas.rewardCue, gain: 0.9)
            Tremor.cheer()
            whisper(Toll.of(
                shards: UInt64(shards), cores: UInt64(cores), resin: UInt64(resin)
            ))
        } else {
            whisper(Vault.say(Lexeme.riteNext), sour: true)
        }
        paint(sheet)
    }
}

/// Obelisk Ascent: the sixty-tier long game roadmap.
final class AscentStage: ScrollStage {
    override var titleLexeme: UInt16? { Lexeme.ascentTitle }
    override var sceneWish: Int? { Canvas.aBgLocation5Scene }

    override func awaken() {
        var scroll = Oracle.shared.ask(Rite.ascent)
        paint(AscentView(&scroll))
    }

    private func paint(_ sheet: AscentView) {
        hoard.show(sheet.purse)
        clear()
        add(chisel(Vault.say(Lexeme.ascentBlurb), Scribe.plain(12), Hide.murmur, lines: 0))
        add(Ledge(
            title: Vault.say(Lexeme.ascentTier) + "  " + "\(sheet.tier)" + " / " + "\(sheet.tierCap)",
            blurb: Vault.say(Lexeme.ascentProgress) + "  "
                + Digits.brief(sheet.light) + " / " + Digits.brief(sheet.next),
            share: sheet.share,
            cast: .raised
        ))

        add(banner(Vault.say(Lexeme.uiAscentRoad)))
        let coins = Lexeme.coinNameAll
        for (step, prize) in sheet.steps.enumerated() {
            var parts: [String] = []
            if prize.shards > 0 { parts.append(Digits.brief(prize.shards) + " " + Vault.say(coins[0])) }
            if prize.cores > 0 { parts.append(Digits.brief(prize.cores) + " " + Vault.say(coins[1])) }
            if prize.resin > 0 { parts.append(Digits.brief(prize.resin) + " " + Vault.say(coins[2])) }
            if prize.extra > 0 { parts.append(Digits.brief(prize.extra) + " " + Vault.say(coins[3])) }
            let title = Vault.say(Lexeme.ascentTier) + " " + "\(step + 1)"
            add(Ledge(
                title: title,
                blurb: parts.joined(separator: "  "),
                cast: prize.taken ? .sunk : (prize.claimable ? .lit : .sunk),
                deed: prize.taken
                    ? Vault.say(Lexeme.navClaimed)
                    : (prize.claimable ? Vault.say(Lexeme.navClaim) : Vault.say(Lexeme.navLocked)),
                deedBuild: prize.claimable ? .gold : .ghost,
                deedLive: prize.claimable,
                fire: { [weak self] in self?.collect(step) }
            ))
        }
    }

    private func collect(_ step: Int) {
        var quill = Quill()
        quill.quad(UInt32(step))
        var scroll = Oracle.shared.ask(Rite.ascentClaim, quill.bytes)
        let taken = scroll.flag()
        let sheet = AscentView(&scroll)
        if taken {
            Oracle.shared.preserve()
            Deck.shared.cue(Canvas.rewardCue, gain: 0.9)
            Tremor.cheer()
        } else {
            whisper(Vault.say(Lexeme.navLocked), sour: true)
        }
        paint(sheet)
    }
}

/// Edicts and Chronicles: daily, weekly and lifetime objectives.
final class EdictsStage: ScrollStage {
    override var titleLexeme: UInt16? { Lexeme.edictsTitle }
    override var sceneWish: Int? { Canvas.bBgRuinedTempleHallScene }

    override func awaken() {
        var scroll = Oracle.shared.ask(Rite.edicts)
        paint(EdictsView(&scroll))
    }

    private func paint(_ sheet: EdictsView) {
        hoard.show(sheet.purse)
        clear()
        add(chisel(
            Vault.say(Lexeme.uiRerollLeft) + "  " + "\(sheet.rerolls)"
                + "   ·   " + Digits.clockFace(sheet.untilDawn),
            Scribe.plain(12), Hide.murmur
        ))

        add(banner(Vault.say(Lexeme.edictsDaily)))
        for (seat, edict) in sheet.dawn.enumerated() {
            add(row(edict, moon: false, seat: seat, rerollable: sheet.rerolls > 0))
        }

        add(banner(Vault.say(Lexeme.edictsWeekly)))
        for (seat, edict) in sheet.moon.enumerated() {
            add(row(edict, moon: true, seat: seat, rerollable: false))
        }

        add(banner(Vault.say(Lexeme.edictsChronicle)))
        for (index, chronicle) in sheet.chronicles.enumerated() {
            add(carve(Ledge(
                title: Vault.say(chronicle.line),
                blurb: Digits.brief(chronicle.done) + " / " + Digits.brief(chronicle.need),
                tailTop: Toll.of(
                    shards: UInt64(chronicle.shardPrize), cores: UInt64(chronicle.corePrize)
                ),
                share: chronicle.share,
                cast: chronicle.taken ? .sunk : (chronicle.ready ? .lit : .sunk),
                deed: chronicle.taken
                    ? Vault.say(Lexeme.navClaimed)
                    : (chronicle.ready ? Vault.say(Lexeme.navClaim) : Vault.say(Lexeme.uiProgress)),
                deedBuild: chronicle.ready ? .gold : .ghost,
                deedLive: chronicle.ready,
                fire: { [weak self] in self?.collectChronicle(index) }
            )))
        }
    }

    private func row(_ edict: EdictView, moon: Bool, seat: Int, rerollable: Bool) -> UIView {
        let card = carve(Ledge(
            title: Vault.say(edict.line),
            blurb: Digits.brief(edict.done) + " / " + Digits.brief(edict.need),
            tailTop: Toll.of(shards: edict.shards, cores: edict.cores, resin: edict.resin),
            tailLow: edict.ready ? Vault.say(Lexeme.uiEdictReady) : nil,
            share: edict.share,
            coolShare: moon,
            cast: edict.taken ? .sunk : (edict.ready ? .lit : .sunk),
            deed: edict.taken
                ? Vault.say(Lexeme.navClaimed)
                : (edict.ready ? Vault.say(Lexeme.navClaim) : Vault.say(Lexeme.edictsReroll)),
            deedBuild: edict.ready ? .gold : .ghost,
            deedLive: edict.ready || (!moon && rerollable && !edict.taken),
            fire: { [weak self] in
                if edict.ready {
                    self?.collectEdict(moon: moon, seat: seat)
                } else {
                    self?.reroll(seat)
                }
            }
        ))
        return card
    }

    private func collectEdict(moon: Bool, seat: Int) {
        var quill = Quill()
        quill.flag(moon)
        quill.quad(UInt32(seat))
        var scroll = Oracle.shared.ask(Rite.edictClaim, quill.bytes)
        let taken = scroll.flag()
        let sheet = EdictsView(&scroll)
        if taken {
            Oracle.shared.preserve()
            Deck.shared.cue(Canvas.rewardCue, gain: 0.85)
            Tremor.cheer()
        }
        paint(sheet)
    }

    private func reroll(_ seat: Int) {
        var quill = Quill()
        quill.quad(UInt32(seat))
        var scroll = Oracle.shared.ask(Rite.edictReroll, quill.bytes)
        let rolled = scroll.flag()
        let sheet = EdictsView(&scroll)
        if rolled {
            Oracle.shared.preserve()
            Deck.shared.cue(Canvas.scrollCue, gain: 0.7)
        } else {
            whisper(Vault.say(Lexeme.navLocked), sour: true)
        }
        paint(sheet)
    }

    private func collectChronicle(_ index: Int) {
        var quill = Quill()
        quill.quad(UInt32(index))
        var scroll = Oracle.shared.ask(Rite.chronicleClaim, quill.bytes)
        let taken = scroll.flag()
        let sheet = EdictsView(&scroll)
        if taken {
            Oracle.shared.preserve()
            Deck.shared.cue(Canvas.missionCompleteCue, gain: 0.85)
            Tremor.cheer()
        }
        paint(sheet)
    }
}

/// Medals: twenty-four milestones that pay out the moment they are struck.
final class MedalsStage: ScrollStage {
    override var titleLexeme: UInt16? { Lexeme.medalsTitle }
    override var sceneWish: Int? { Canvas.bBgPyramidCoreChamberScene }

    override func awaken() {
        var scroll = Oracle.shared.ask(Rite.medals)
        let sheet = MedalsView(&scroll)
        hoard.show(sheet.purse)
        clear()
        let won = sheet.medals.filter(\.won).count
        add(chisel(
            Vault.say(Lexeme.uiProgress) + "  " + "\(won)" + " / " + "\(sheet.medals.count)",
            Scribe.tally(13), Hide.gild
        ))
        for (index, medal) in sheet.medals.enumerated() {
            add(Ledge(
                title: Vault.say(medal.name),
                blurb: Vault.say(medal.blurb),
                tailTop: Digits.brief(medal.done) + " / " + Digits.brief(medal.need),
                tailLow: Toll.of(
                    shards: UInt64(medal.shardPrize), cores: UInt64(medal.corePrize)
                ),
                share: medal.share,
                art: medal.won ? Vault.prop(Canvas.aAncientRelics[index % 4]) : nil,
                cast: medal.won ? .lit : .sunk
            ))
        }
    }
}

/// Codex: the in-game manual, filled in as the player meets each piece.
final class CodexStage: ScrollStage {
    /// One screen per atlas section, so a reader never scrolls past three
    /// tables to reach the one they opened.
    enum Leaf {
        case lore
        case breeds
        case tiles
        case goals
    }

    private let leaf: Leaf

    init(_ leaf: Leaf) {
        self.leaf = leaf
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override var titleLexeme: UInt16? {
        switch leaf {
        case .lore: return Lexeme.atlasTabCodex
        case .breeds: return Lexeme.atlasTabBestiary
        case .tiles: return Lexeme.atlasTabTiles
        case .goals: return Lexeme.atlasTabGoals
        }
    }

    override var sceneWish: Int? { Canvas.bBgObservatoryControlHallScene }

    override func awaken() {
        var scroll = Oracle.shared.ask(Rite.codex)
        let sheet = CodexView(&scroll)
        hoard.show(sheet.purse)
        clear()

        switch leaf {
        case .lore:
            for entry in sheet.entries {
                add(Ledge(
                    title: entry.found ? Vault.say(entry.title) : Vault.say(Lexeme.navLocked),
                    blurb: entry.found ? Vault.say(entry.body) : Vault.say(Lexeme.uiCodexSealed),
                    cast: entry.found ? .raised : .sunk
                ))
            }
        case .breeds:
            for (index, breed) in sheet.breeds.enumerated() {
                add(Ledge(
                    title: Vault.say(breed.0),
                    blurb: Vault.say(breed.1),
                    art: Vault.prop(Relief.huskProp(UInt8(index))),
                    cast: .sunk
                ))
            }
        case .tiles:
            for (index, tile) in sheet.tiles.enumerated() {
                add(Ledge(
                    title: Vault.say(tile.0),
                    blurb: Vault.say(tile.1),
                    art: Vault.prop(Relief.guideProp(index)),
                    cast: .sunk
                ))
            }
        case .goals:
            for goal in sheet.goals {
                add(Ledge(title: Vault.say(goal.0), blurb: Vault.say(goal.1), cast: .raised))
            }
        }
    }
}

/// Records: the full statistics sheet.
final class RecordsStage: ScrollStage {
    override var titleLexeme: UInt16? { Lexeme.statsTitle }
    override var sceneWish: Int? { Canvas.bBgCityRuinsScene }

    override func awaken() {
        var scroll = Oracle.shared.ask(Rite.records)
        let sheet = RecordsView(&scroll)
        hoard.show(sheet.purse)
        clear()

        add(banner(Vault.say(Lexeme.uiTotals)))
        let gauges: [(UInt16, UInt32, UInt32)] = [
            (Lexeme.mapStars, sheet.seals, sheet.sealCap),
            (Lexeme.relicTitle, sheet.relics, sheet.relicCap),
            (Lexeme.medalsTitle, sheet.medals, sheet.medalCap),
            (Lexeme.latticeTitle, sheet.latticeRanks, sheet.latticeCap),
        ]
        for (lexeme, done, need) in gauges {
            add(Ledge(
                title: Vault.say(lexeme),
                tailTop: "\(done)" + " / " + "\(need)",
                share: Float(done) / Float(max(1, need)),
                cast: done >= need ? .lit : .sunk
            ))
        }

        add(banner(Vault.say(Lexeme.statsTitle)))
        for (lexeme, value) in sheet.lines {
            add(Ledge(
                title: Vault.say(lexeme),
                tailTop: Digits.brief(value),
                cast: .sunk
            ))
        }
        add(Ledge(
            title: Vault.say(Lexeme.reawakenTitle),
            blurb: Vault.say(Lexeme.reawakenBlurb),
            tailTop: "\(sheet.reawakenings)",
            cast: sheet.wholeWorldWoken ? .lit : .sunk
        ))
    }
}
