import SpriteKit
import UIKit

/// The run. One screen for the whole descent: the chamber being fought in,
/// what it wants, what the hero has left, and the sheets that come between
/// chambers.
///
/// The fight is live. Every frame the scene hands up where the thumb is
/// pushing, this sends it to the core, and whatever comes back is drawn. No
/// rule is decided here.
final class DelveStage: Stage {
    override var titleLexeme: UInt16? { nil }
    override var wantsPurse: Bool { false }
    override var hidesDock: Bool { true }
    override var sceneWish: Int? { Canvas.aBgRoom1Scene }

    private let board = SKView()
    private let reins = ReinsPad()
    private let canvasScene = ArenaCanvas(size: CGSize(width: 320, height: 512))

    private let leave = PressPad(.ghost)
    private let roomLine = chisel("", Scribe.carved(15, .bold), Hide.gild, align: .center)
    private let waveLine = chisel("", Scribe.tally(12), Hide.murmur, align: .right)
    private let goalLine = chisel("", Scribe.carved(14, .semibold), Hide.parchment)
    private let tally = chisel("", Scribe.tally(12), Hide.gild, align: .right)
    private let coinLine = chisel("", Scribe.tally(12), Hide.gild, align: .left)

    private let life = Meter(thickness: 9)
    private let lifeTag = chisel("", Scribe.tally(12), Hide.parchment)
    /// Shown only while the beer is still in charge, because the hero fights
    /// differently for those six seconds and the player should know why.
    private let brewTag = chisel("", Scribe.tally(12), Hide.ember)
    private let brewMug = UIImageView(image: Relief.brewArt)
    private let focusRow = UIStackView()
    private let skillRow = UIStackView()
    private var skillPads: [PressPad] = []

    private let sheet = Sheet()

    private var state = DelveView()
    private var wornScene = -1
    /// Frames are cheap, text is not: the labels are refreshed a few times a
    /// second rather than sixty.
    private var dressDue: CFTimeInterval = 0
    private var keepDue: CFTimeInterval = 0
    private var fighting = false
    /// A line is held for a beat before the next one, or the hero gabbles
    /// over herself in a crowd.
    private var hush: CFTimeInterval = 0
    private var said = 0

    // --- building ----------------------------------------------------------

    override func assemble() {
        let header = UIStackView(arrangedSubviews: [leave, roomLine, waveLine])
        header.axis = .horizontal
        header.spacing = Grid.gap
        header.alignment = .center
        leave.dress(Vault.say(Lexeme.navBack))
        leave.onPress = { [weak self] in self?.askToLeave() }
        leave.measure(74, Grid.touch - 6)
        waveLine.setContentHuggingPriority(.required, for: .horizontal)

        let goalCard = Slab(.sunk)
        let goalBox = UIStackView(arrangedSubviews: [goalLine, tally])
        goalBox.axis = .horizontal
        goalBox.spacing = Grid.gap
        goalBox.alignment = .center
        tally.setContentHuggingPriority(.required, for: .horizontal)
        goalBox.translatesAutoresizingMaskIntoConstraints = false
        goalCard.addSubview(goalBox)
        NSLayoutConstraint.activate([
            goalBox.topAnchor.constraint(equalTo: goalCard.topAnchor, constant: Grid.tight),
            goalBox.leadingAnchor.constraint(equalTo: goalCard.leadingAnchor, constant: Grid.inset),
            goalBox.trailingAnchor.constraint(equalTo: goalCard.trailingAnchor, constant: -Grid.inset),
            goalBox.bottomAnchor.constraint(equalTo: goalCard.bottomAnchor, constant: -Grid.tight),
        ])

        focusRow.axis = .horizontal
        focusRow.spacing = 4
        focusRow.alignment = .center
        focusRow.setContentHuggingPriority(.required, for: .horizontal)
        brewTag.text = Vault.say(Lexeme.runDrunk)
        brewTag.isHidden = true
        brewTag.setContentHuggingPriority(.required, for: .horizontal)
        brewMug.contentMode = .scaleAspectFit
        brewMug.isHidden = true
        brewMug.measure(16, 18)
        let vitals = UIStackView(arrangedSubviews: [lifeTag, life, focusRow, brewMug, brewTag, coinLine])
        vitals.axis = .horizontal
        vitals.spacing = Grid.gap
        vitals.alignment = .center
        lifeTag.setContentHuggingPriority(.required, for: .horizontal)
        coinLine.setContentHuggingPriority(.required, for: .horizontal)

        board.backgroundColor = .clear
        board.allowsTransparency = true
        board.translatesAutoresizingMaskIntoConstraints = false
        board.preferredFramesPerSecond = 60
        board.isMultipleTouchEnabled = true
        canvasScene.onPulse = { [weak self] x, y, span in self?.pulse(x, y, span) }
        board.presentScene(canvasScene)

        skillRow.axis = .horizontal
        skillRow.spacing = Grid.tight
        skillRow.distribution = .fillEqually

        let column = UIStackView(arrangedSubviews: [header, goalCard, vitals, board, skillRow])
        column.axis = .vertical
        column.spacing = Grid.gap
        column.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: canvas.safeAreaLayoutGuide.topAnchor, constant: Grid.tight),
            column.leadingAnchor.constraint(equalTo: canvas.leadingAnchor, constant: Grid.gutter),
            column.trailingAnchor.constraint(equalTo: canvas.trailingAnchor, constant: -Grid.gutter),
            column.bottomAnchor.constraint(
                equalTo: canvas.safeAreaLayoutGuide.bottomAnchor, constant: -Grid.gap
            ),
            skillRow.heightAnchor.constraint(equalToConstant: 74),
        ])
        board.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        // The thumb pad lives above the fight, so no sprite, label or sheet
        // can ever end up between a thumb and the hero.
        reins.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(reins)
        NSLayoutConstraint.activate([
            reins.topAnchor.constraint(equalTo: board.topAnchor),
            reins.leadingAnchor.constraint(equalTo: board.leadingAnchor),
            reins.trailingAnchor.constraint(equalTo: board.trailingAnchor),
            reins.bottomAnchor.constraint(equalTo: board.bottomAnchor),
        ])

        sheet.install(over: view)
    }

    override func awaken() {
        let (_, fresh) = Oracle.shared.descend(Rite.delveView, verdict: false)
        settle(fresh, full: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Nothing ticks while the screen is away, and whatever happened is
        // written down before it goes.
        fighting = false
        Oracle.shared.preserve(force: true)
    }

    // --- the live fight -----------------------------------------------------

    /// One frame. The core is told how long the frame took and where the thumb
    /// is, and it answers with the whole chamber.
    private func pulse(_ pushX: Int, _ pushY: Int, _ span: UInt32) {
        guard fighting, span > 0 else { return }
        let (leanX, leanY) = canvasScene.driving ? (pushX, pushY) : reins.push
        var quill = Quill()
        quill.signed(Int32(leanX))
        quill.signed(Int32(leanY))
        quill.quad(span)
        let (_, fresh) = Oracle.shared.descend(Rite.delveAct, quill.bytes)
        settle(fresh, full: false)
    }

    private func unleash(_ slot: Int) {
        let (dx, dy) = reins.aim
        var quill = Quill()
        quill.byte(UInt8(slot))
        quill.signed(Int32(dx))
        quill.signed(Int32(dy))
        let (spent, fresh) = Oracle.shared.descend(Rite.delveKnack, quill.bytes)
        if !spent {
            Tremor.scold()
            whisper(Vault.say(Lexeme.runNoFocus), sour: true)
        } else {
            Deck.shared.cue(Canvas.ancientMechanismActivatedCue, gain: 0.6)
        }
        settle(fresh, full: true)
    }

    private func askToLeave() {
        fighting = false
        sheet.ask(
            title: Vault.say(Lexeme.navLeave),
            blurb: Vault.say(Lexeme.runLeaveAsk),
            yes: Vault.say(Lexeme.navConfirm),
            no: Vault.say(Lexeme.navCancel)
        ) { [weak self] agreed in
            guard agreed else {
                self?.fighting = self?.state.leg == Leg.fight
                return
            }
            _ = Oracle.shared.ask(Rite.delveAbandon)
            Oracle.shared.preserve(force: true)
            Director.shared.back()
        }
    }

    // --- showing what came back -------------------------------------------

    /// Each region has its own chamber art, so a descent looks like the place
    /// it is dug out of.
    private static let chambers = [
        Canvas.aUniversalBgEntranceScene,
        Canvas.bBgOasisShrineScene,
        Canvas.bBgRuinedTempleHallScene,
        Canvas.bBgPyramidCoreChamberScene,
        Canvas.bBgObservatoryScene,
        Canvas.bBgUndergroundMechanismComplexScene,
        Canvas.bBgGreatWheelOfMaatChamberScene,
    ]

    private func settle(_ fresh: DelveView, full: Bool) {
        let legChanged = fresh.leg != state.leg
        state = fresh
        guard fresh.live, let room = fresh.room else {
            Director.shared.back()
            return
        }
        fighting = fresh.leg == Leg.fight

        let now = CACurrentMediaTime()
        if now > keepDue {
            keepDue = now + 4
            Oracle.shared.preserve()
        }
        if wornScene != Int(fresh.region) {
            wornScene = Int(fresh.region)
            let look = DelveStage.chambers[Int(fresh.region) % DelveStage.chambers.count]
            redress(scene: look)
            canvasScene.ground(Int(fresh.region))
        }

        canvasScene.show(room)
        speak(room)

        if full || legChanged || now > dressDue {
            dressDue = now + 0.2
            dressChrome(fresh, room)
        }
        if legChanged || full {
            raiseSheet(fresh)
        }
    }

    private func dressChrome(_ fresh: DelveView, _ room: RoomView) {
        roomLine.text = Vault.say(Lexeme.runRoom)
            .replacingOccurrences(of: "%1", with: "\(fresh.depth + 1)")
            .replacingOccurrences(of: "%2", with: "\(fresh.rows)")
        waveLine.text = Vault.say(Lexeme.runWave) + " \(room.wave)/\(room.waves)"
        goalLine.text = Vault.say(fresh.goalLine)
        tally.text = countdown(room)
        coinLine.text = "\(room.coins)"

        lifeTag.text = "\(max(0, room.hp))/\(room.hpCap)"
            + (room.shield > 0 ? "  +\(room.shield)" : "")
        life.pour(room.lifeShare)
        brewTag.isHidden = !room.drunk
        brewMug.isHidden = !room.drunk
        dressFocus(room)
        dressSkills(fresh)
    }

    /// The one number that says how close the chamber is to being finished.
    private func countdown(_ room: RoomView) -> String {
        if room.portalOpen {
            return Vault.say(Lexeme.runStairsOpen)
        }
        switch room.goal {
        case Errand.endure, Errand.flee:
            return Vault.say(Lexeme.runHold) + " \(room.holdLeft)"
        case Errand.hoard:
            let left = room.motes.filter { $0.kind == Pickup.chest }.count
            return Vault.say(Lexeme.runChests) + " \(left)"
        default:
            return Vault.say(Lexeme.runEnemies) + " \(room.foesLeft)"
        }
    }

    private func dressFocus(_ room: RoomView) {
        let want = Int(room.focusCap)
        if focusRow.arrangedSubviews.count != want {
            for spare in focusRow.arrangedSubviews {
                focusRow.removeArrangedSubview(spare)
                spare.removeFromSuperview()
            }
            for _ in 0..<want {
                let bead = UIView()
                bead.layer.cornerRadius = 4
                bead.measure(8, 8)
                focusRow.addArrangedSubview(bead)
            }
        }
        for (slot, bead) in focusRow.arrangedSubviews.enumerated() {
            bead.backgroundColor = slot < Int(room.focus) ? Hide.lapis : Hide.ink(40, 48, 44)
        }
    }

    private func dressSkills(_ fresh: DelveView) {
        if skillPads.count != fresh.seats.count {
            for spare in skillRow.arrangedSubviews {
                skillRow.removeArrangedSubview(spare)
                spare.removeFromSuperview()
            }
            skillPads = fresh.seats.enumerated().map { slot, _ in
                let pad = PressPad(.stone)
                pad.onPress = { [weak self] in self?.unleash(slot) }
                skillRow.addArrangedSubview(pad)
                return pad
            }
        }
        for (slot, seat) in fresh.seats.enumerated() where skillPads.indices.contains(slot) {
            let pad = skillPads[slot]
            if seat.filled {
                let note = seat.rest > 0
                    ? Vault.say(Lexeme.powerRest)
                    : "\(seat.toll)"
                // The jar is the one knack with a face: it is the last seat,
                // it is always there, and a tankard reads faster than two
                // words of English, so it goes on the pad instead of them.
                if slot == fresh.seats.count - 1 {
                    pad.dress("", note: note, art: Relief.brewArt)
                } else {
                    pad.dress(Vault.say(seat.name), note: note)
                }
                pad.isEnabled = seat.ready
                pad.build = seat.ready ? .gold : .stone
            } else {
                pad.dress(Vault.say(Lexeme.powerEmpty))
                pad.isEnabled = false
                pad.build = .ghost
            }
        }
    }

    private func speak(_ room: RoomView) {
        for flash in room.flashes {
            switch flash.kind {
            case Omen.slay:
                Deck.shared.cue(Canvas.ancientMechanismActivatedCue, gain: 0.7)
                mouth(Lexeme.barkKillAll)
            case Omen.took:
                Tremor.scold()
                mouth(Lexeme.barkHurtAll)
            case Omen.swill:
                Deck.shared.cue(Canvas.windowOpenCue, gain: 0.8)
                mouth(Lexeme.barkSwigAll)
            case Omen.coin:
                Deck.shared.cue(Canvas.coinPickupCue, gain: 0.7)
            default:
                break
            }
        }
    }

    /// One line from a pool, and not the same one twice in a row. The hero is
    /// a tomb robber in a crumbling temple and she talks like one.
    private func mouth(_ pool: [UInt16]) {
        let now = CACurrentMediaTime()
        guard !pool.isEmpty, now > hush else { return }
        hush = now + 0.7
        said = (said + 1 + Int(arc4random_uniform(UInt32(max(1, pool.count - 1))))) % pool.count
        canvasScene.bark(Vault.say(pool[said]))
    }

    // --- the sheets between chambers ---------------------------------------

    private func raiseSheet(_ fresh: DelveView) {
        switch fresh.leg {
        case Leg.fight:
            sheet.dismiss()
        case Leg.card:
            sheet.tell(
                title: Vault.say(Lexeme.runWinTitle),
                blurb: Vault.say(Lexeme.runWinBlurb),
                deed: Vault.say(Lexeme.navContinue)
            ) { [weak self] in self?.press() }
        case Leg.cache:
            sheet.choose(
                title: Vault.say(Lexeme.runBoonTitle),
                blurb: Vault.say(Lexeme.runBoonBlurb),
                picks: fresh.cache.map { (Vault.say($0.name), Vault.say($0.blurb)) }
            ) { [weak self] choice in self?.takeBoon(choice) }
        case Leg.haven:
            sheet.tell(
                title: Vault.say(
                    fresh.haunt == Haunt.trader ? Lexeme.runTraderTitle : Lexeme.runCampTitle
                ),
                blurb: Vault.say(
                    fresh.haunt == Haunt.trader ? Lexeme.runTraderBlurb : Lexeme.runCampBlurb
                ),
                deed: Vault.say(Lexeme.navContinue),
                picks: fresh.haunt == Haunt.trader
                    ? fresh.wares.enumerated().map { seat, ware in
                        (
                            Vault.say(ware.name),
                            Vault.say(ware.blurb) + "  ·  " + Toll.of(shards: ware.toll),
                            ware.affordable,
                            { [weak self] in self?.trade(seat) }
                        )
                    }
                    : []
            ) { [weak self] in self?.press() }
        case Leg.fork:
            let lanes = fresh.map.indices.contains(Int(fresh.depth) + 1)
                ? fresh.map[Int(fresh.depth) + 1]
                : []
            sheet.choose(
                title: Vault.say(Lexeme.runForkTitle),
                blurb: Vault.say(Lexeme.runForkBlurb),
                picks: lanes.enumerated().compactMap { _, stop in
                    stop.open ? (Vault.say(stop.name), Vault.say(stop.blurb)) : nil
                },
                keys: lanes.enumerated().compactMap { lane, stop in stop.open ? lane : nil }
            ) { [weak self] lane in self?.walk(lane) }
        case Leg.crowned, Leg.fallen:
            let won = fresh.leg == Leg.crowned
            sheet.tell(
                title: Vault.say(won ? Lexeme.runDoneTitle : Lexeme.runFailTitle),
                blurb: Vault.say(won ? Lexeme.runDoneBlurb : Lexeme.runFailBlurb)
                    + "\n" + Vault.say(Lexeme.runSpoils) + "  "
                    + Toll.of(
                        shards: fresh.spoils.shards,
                        cores: fresh.spoils.cores,
                        resin: fresh.spoils.resin
                    ),
                deed: Vault.say(Lexeme.navOk)
            ) {
                Oracle.shared.preserve(force: true)
                Saga.shared.show(chapter: Int(fresh.region), won: won) {
                    Director.shared.back()
                }
            }
        default:
            sheet.dismiss()
        }
    }

#if DEBUG
    /// Hands the stick to the canvas so a fight plays itself for a screenshot.
    func rehearse() {
        canvasScene.rehearse()
    }
#endif

    private func press() {
        let (_, fresh) = Oracle.shared.descend(Rite.delvePress)
        settle(fresh, full: true)
    }

    private func takeBoon(_ choice: Int) {
        let (_, fresh) = Oracle.shared.descend(Rite.delveBoon, Quill.of(quad: UInt32(choice)))
        settle(fresh, full: true)
    }

    private func walk(_ lane: Int) {
        let (_, fresh) = Oracle.shared.descend(Rite.delveFork, Quill.of(quad: UInt32(lane)))
        settle(fresh, full: true)
    }

    private func trade(_ seat: Int) {
        let (bought, fresh) = Oracle.shared.descend(Rite.delveTrade, Quill.of(quad: UInt32(seat)))
        if !bought { whisper(Vault.say(Lexeme.runTraderBroke), sour: true) }
        settle(fresh, full: true)
    }
}
