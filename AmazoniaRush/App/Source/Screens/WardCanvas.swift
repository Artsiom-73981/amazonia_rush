import CoreImage
import SpriteKit

/// The fight, drawn. It owns no rules: every frame it is handed a chamber in
/// world units and it moves its sprites to match, then it hands back where the
/// player's thumb is pushing.
///
/// The whole chamber is on screen at once, so there is no camera to chase and
/// nothing to scroll: the world is mapped onto the glass by one scale factor.
final class ArenaCanvas: SKScene {
    /// Called once a frame with the thumbstick, in -1000..1000 per axis, and
    /// the milliseconds since the last call.
    var onPulse: ((Int, Int, UInt32) -> Void)?
    /// True while a debug build is playing itself, in which case the push
    /// handed up by this scene is the one to obey.
    var driving: Bool {
        #if DEBUG
        return rehearsing
        #else
        return false
        #endif
    }

    private let shade = SKNode()
    private let rubble = SKNode()
    private let litter = SKNode()
    private let bodies = SKNode()
    private let flying = SKNode()
    private let sparks = SKNode()

    private var span = CGSize(width: 1000, height: 1600)
    private var grain: CGFloat = 1
    private var ledge = CGPoint.zero

    private var walker: SKNode?
    private var walkerShell: SKSpriteNode?
    private var worn = Face.near
    private var tipsy = false
    private var halo: SKShapeNode?
    private var gate: SKNode?
    private var stones: [SKNode] = []
    private var crowd: [UInt32: SKNode] = [:]
    private var tracer: [UInt32: SKNode] = [:]
    private var loose: [UInt32: SKNode] = [:]

    private var latest: RoomView?
    /// Fingerprint of the stones the floor was drawn around. A new chamber
    /// means new stones, which is how one is told from the next.
    private var mason = 0
    /// Every stain on the floor, oldest first, so the oldest can be let go of
    /// when the floor has had enough.
    private var spill: [SKNode] = []
    #if DEBUG
    /// Screenshot aid: drives the stick itself so a fight can be watched on a
    /// headless simulator. Debug builds only.
    private var rehearsing = false
    private var stalled = 0
    func rehearse() { rehearsing = true }
    #endif

    private var last: TimeInterval = 0
    private var laid = false

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        scaleMode = .resizeFill
        for layer in [shade, rubble, litter, bodies, flying, sparks] {
            addChild(layer)
        }
        shade.zPosition = 0
        rubble.zPosition = 10
        litter.zPosition = 20
        bodies.zPosition = 30
        flying.zPosition = 60
        sparks.zPosition = 70
    }

    // --- mapping the world onto the glass ----------------------------------

    private func measure() {
        let fit = min(size.width / span.width, size.height / span.height)
        grain = fit
        ledge = CGPoint(
            x: (size.width - span.width * fit) / 2,
            y: (size.height - span.height * fit) / 2
        )
    }

    private func spot(_ x: Int32, _ y: Int32) -> CGPoint {
        CGPoint(
            x: ledge.x + CGFloat(x) * grain,
            y: size.height - ledge.y - CGFloat(y) * grain
        )
    }

    private func reading(_ point: CGPoint) -> (Int, Int) {
        (
            Int((point.x - ledge.x) / max(grain, 0.001)),
            Int((size.height - ledge.y - point.y) / max(grain, 0.001))
        )
    }

    /// Depth order: whatever stands lower on the floor is drawn in front.
    private func rank(_ y: Int32, _ lift: CGFloat = 0) -> CGFloat {
        CGFloat(span.height - CGFloat(y)) * 0.01 + lift
    }

    private func carving(_ art: SKTexture, _ reach: CGFloat) -> SKSpriteNode {
        let piece = SKSpriteNode(texture: art)
        let shape = art.size()
        let fit = reach / max(shape.width, shape.height)
        piece.size = CGSize(width: shape.width * fit, height: shape.height * fit)
        return piece
    }

    // --- the floor ---------------------------------------------------------

    /// Which region's palette the ground is mixed from.
    private var bedrock = 0

    func ground(_ region: Int) {
        guard region != bedrock else { return }
        bedrock = region
        laid = false
    }

    /// One painting per region, each of them a hall seen down its length, so
    /// the walls of the art are the walls of the chamber and the player can
    /// see at a glance where the floor ends.
    private static let beds = [
        Canvas.aBgRoom1Scene,
        Canvas.bBgOasisShrineScene,
        Canvas.aBgRoom3Scene,
        Canvas.bBgDesertTempleChamberScene,
        Canvas.bBgObservatoryControlHallScene,
        Canvas.bBgUndergroundTempleScene,
        Canvas.bBgGreatWheelOfMaatChamberScene,
    ]

    /// The floor, laid once per chamber: the region's own painting, filled to
    /// the bounds and pulled down under a veil so sprites read against it,
    /// with the corners sunk in shadow. No tiling, no pattern, no grid.
    private func layFloor() {
        shade.removeAllChildren()
        litter.removeAllChildren()
        let field = CGRect(
            x: ledge.x, y: ledge.y,
            width: span.width * grain, height: span.height * grain
        )

        let apron = SKShapeNode(rect: field)
        apron.fillColor = Hide.ink(46, 36, 26)
        apron.strokeColor = .clear
        shade.addChild(apron)

        let look = ArenaCanvas.beds[abs(bedrock) % ArenaCanvas.beds.count]
        if let art = Vault.scene(look) {
            let hide = SKCropNode()
            let stencil = SKShapeNode(rect: field)
            stencil.fillColor = .white
            stencil.strokeColor = .clear
            hide.maskNode = stencil

            let sheet = SKSpriteNode(texture: SKTexture(image: art))
            let shape = sheet.texture?.size() ?? field.size
            // Only the near end of the painting is used, the part that is
            // actually floor. Its far wall and ceiling are left off the top,
            // so nothing ever stands in mid air.
            let share: CGFloat = 0.58
            let fill = max(field.width / shape.width, field.height / share / shape.height)
            sheet.size = CGSize(width: shape.width * fill, height: shape.height * fill)
            sheet.position = CGPoint(x: field.midX, y: field.minY + sheet.size.height / 2)
            hide.addChild(sheet)
            shade.addChild(hide)

            let veil = SKShapeNode(rect: field)
            veil.fillColor = Hide.pitch.withAlphaComponent(0.34)
            veil.strokeColor = .clear
            shade.addChild(veil)
        }

        // Shadow gathered along the walls, so the bounds are felt rather than
        // drawn as a line.
        for step in 0..<7 {
            let inset = CGFloat(step) * 9
            let edge = SKShapeNode(rect: field.insetBy(dx: inset, dy: inset))
            edge.fillColor = .clear
            edge.strokeColor = Hide.pitch.withAlphaComponent(0.075)
            edge.lineWidth = 10
            shade.addChild(edge)
        }
        let lip = SKShapeNode(rect: field)
        lip.fillColor = .clear
        lip.strokeColor = Hide.gild.withAlphaComponent(0.3)
        lip.lineWidth = 2
        shade.addChild(lip)

        strewFloor()
    }

    /// Sand drifts, scrub and odd bits of temple, scattered the same way every
    /// time for one chamber so the floor does not crawl between frames.
    private func strewFloor() {
        var churn = UInt32(truncatingIfNeeded: mason &* 2654435761 &+ 48611) | 1
        func roll(_ ceiling: Int) -> Int {
            churn ^= churn << 13
            churn ^= churn >> 17
            churn ^= churn << 5
            return Int(churn % UInt32(max(1, ceiling)))
        }
        // Whoever was here before the player, and did not leave. Laid down
        // first, so sand and scrub drift over them.
        for _ in 0..<3 {
            let x = Int32(roll(Int(span.width) - 200) + 100)
            let y = Int32(roll(Int(span.height) - 420) + 300)
            guard let art = Relief.remains(roll(4)) else { continue }
            let body = carving(art, CGFloat(roll(80) + 170) * grain)
            body.position = spot(x, y)
            body.zPosition = 2
            body.alpha = 0.82
            body.color = Hide.pitch
            body.colorBlendFactor = 0.3
            body.zRotation = CGFloat(roll(70) - 35) / 100
            body.xScale = roll(2) == 0 ? -1 : 1
            shade.addChild(body)
            if Deck.shared.goreOn {
                oldBlood(spot(x, y), reach: CGFloat(roll(60) + 90))
            }
        }
        for _ in 0..<8 {
            let x = Int32(roll(Int(span.width) - 120) + 60)
            let y = Int32(roll(Int(span.height) - 300) + 220)
            guard let art = Relief.litter(roll(7)) else { continue }
            let piece = carving(art, CGFloat(roll(60) + 90) * grain)
            piece.position = spot(x, y)
            piece.zPosition = 1
            piece.alpha = 0.6
            piece.color = Hide.pitch
            piece.colorBlendFactor = 0.18
            piece.xScale = roll(2) == 0 ? -1 : 1
            shade.addChild(piece)
        }
    }

    private func layStones(_ room: RoomView) {
        for spare in stones { spare.removeFromParent() }
        stones.removeAll()
        for stone in room.stones {
            let nest = SKNode()
            nest.position = spot(stone.x, stone.y)
            nest.zPosition = rank(stone.y, 2)
            let base = SKShapeNode(ellipseOf: CGSize(
                width: CGFloat(stone.girth) * grain * 2.1,
                height: CGFloat(stone.girth) * grain * 0.9
            ))
            base.fillColor = Hide.pitch.withAlphaComponent(0.42)
            base.strokeColor = .clear
            nest.addChild(base)
            if let art = Relief.pillar(Int(stone.look)) {
                let piece = carving(art, CGFloat(stone.girth) * grain * 3.1)
                piece.anchorPoint = CGPoint(x: 0.5, y: 0.18)
                nest.addChild(piece)
            }
            rubble.addChild(nest)
            stones.append(nest)
        }
    }

    private func layGate(_ room: RoomView) {
        if gate == nil {
            let nest = SKNode()
            if let art = Relief.doorway() {
                let piece = carving(art, 180 * grain)
                piece.anchorPoint = CGPoint(x: 0.5, y: 0.2)
                nest.addChild(piece)
            }
            let glow = SKShapeNode(circleOfRadius: 70 * grain)
            glow.fillColor = Hide.lapis.withAlphaComponent(0.22)
            glow.strokeColor = Hide.lapis
            glow.lineWidth = 2
            glow.run(.repeatForever(.sequence([
                .scale(to: 1.12, duration: 0.7),
                .scale(to: 0.94, duration: 0.7),
            ])))
            nest.addChild(glow)
            nest.alpha = 0
            rubble.addChild(nest)
            gate = nest
        }
        gate?.position = spot(room.portalX, room.portalY)
        gate?.zPosition = rank(room.portalY, 1)
        gate?.alpha = room.portalOpen ? 1 : 0
    }

    // --- the cast ----------------------------------------------------------

    private func raiseWalker() {
        guard walker == nil else { return }
        let nest = SKNode()
        let pool = SKShapeNode(ellipseOf: CGSize(width: 190 * grain, height: 190 * grain))
        pool.fillColor = Hide.gild.withAlphaComponent(0.13)
        pool.strokeColor = .clear
        pool.blendMode = .add
        nest.addChild(pool)

        let ring = SKShapeNode(ellipseOf: CGSize(width: 96 * grain, height: 38 * grain))
        ring.fillColor = Hide.gild.withAlphaComponent(0.2)
        ring.strokeColor = Hide.gild
        ring.lineWidth = 3
        nest.addChild(ring)
        halo = ring
        if let art = Relief.keeper(.near) {
            let piece = carving(art, 340 * grain)
            piece.anchorPoint = CGPoint(x: 0.5, y: 0.08)
            nest.addChild(piece)
            walkerShell = piece
        }
        bodies.addChild(nest)
        walker = nest
    }

    /// Which of the four Keepers to show. Sideways wins over forwards, so a
    /// diagonal run reads as a run and not as a shuffle toward the player.
    private func turn(_ room: RoomView) {
        let facing: Face
        if abs(room.lookX) > abs(room.lookY) {
            facing = room.lookX < 0 ? .left : .right
        } else {
            facing = room.lookY < 0 ? .away : .near
        }
        guard facing != worn, let art = Relief.keeper(facing) else { return }
        worn = facing
        walkerShell?.texture = art
        let shape = art.size()
        let fit = 340 * grain / max(shape.width, shape.height)
        walkerShell?.size = CGSize(width: shape.width * fit, height: shape.height * fit)
    }

    private func dressCrowd(_ room: RoomView) {
        var seen = Set<UInt32>()
        for beast in room.brood {
            seen.insert(beast.tag)
            let nest = crowd[beast.tag] ?? raiseBeast(beast)
            nest.position = spot(beast.x, beast.y)
            nest.zPosition = rank(beast.y, 3)
            if let shell = nest.childNode(withName: Mark.shell) as? SKSpriteNode {
                shell.xScale = beast.lookX < 0 ? -abs(shell.xScale) : abs(shell.xScale)
                shell.color = beast.mood == Mood.hurt ? Hide.ember : Hide.pitch
                shell.colorBlendFactor = beast.mood == Mood.hurt ? 0.6 : 0
            }
            if let bar = nest.childNode(withName: Mark.pip) as? SKShapeNode {
                bar.xScale = max(0.04, CGFloat(beast.share))
            }
            if let tell = nest.childNode(withName: Mark.tell) as? SKShapeNode {
                tell.alpha = beast.mood == Mood.wind ? 1 : 0
            }
        }
        for (tag, nest) in crowd where !seen.contains(tag) {
            crowd.removeValue(forKey: tag)
            nest.run(.sequence([
                .group([.fadeOut(withDuration: 0.18), .scale(to: 0.6, duration: 0.18)]),
                .removeFromParent(),
            ]))
        }
    }

    private func raiseBeast(_ beast: BeastView) -> SKNode {
        let nest = SKNode()
        let reach = CGFloat(beast.girth) * grain
        let base = SKShapeNode(ellipseOf: CGSize(width: reach * 2.1, height: reach * 0.8))
        base.fillColor = Hide.pitch.withAlphaComponent(0.45)
        base.strokeColor = .clear
        nest.addChild(base)

        let tell = SKShapeNode(circleOfRadius: reach * 1.5)
        tell.name = Mark.tell
        tell.fillColor = Hide.ember.withAlphaComponent(0.16)
        tell.strokeColor = Hide.ember
        tell.lineWidth = 2
        tell.alpha = 0
        tell.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.4, duration: 0.2),
            .fadeAlpha(to: 1, duration: 0.2),
        ])))
        nest.addChild(tell)

        if let art = Relief.husk(beast.breed) {
            let piece = carving(art, reach * (beast.boss ? 7.0 : 5.0))
            piece.name = Mark.shell
            piece.anchorPoint = CGPoint(x: 0.5, y: 0.14)
            nest.addChild(piece)
        }

        let trough = SKShapeNode(rect: CGRect(
            x: -reach, y: reach * 2.4, width: reach * 2, height: 5
        ))
        trough.fillColor = Hide.pitch.withAlphaComponent(0.7)
        trough.strokeColor = .clear
        nest.addChild(trough)
        let pip = SKShapeNode(rect: CGRect(
            x: -reach, y: reach * 2.4, width: reach * 2, height: 5
        ))
        pip.name = Mark.pip
        pip.fillColor = beast.boss ? Hide.ember : Hide.bruise
        pip.strokeColor = .clear
        pip.xScale = 1
        nest.addChild(pip)

        nest.setScale(0.4)
        nest.run(.scale(to: 1, duration: 0.2))
        bodies.addChild(nest)
        crowd[beast.tag] = nest
        return nest
    }

    private func dressShots(_ room: RoomView) {
        var seen = Set<UInt32>()
        for shot in room.shots {
            seen.insert(shot.tag)
            let nest = tracer[shot.tag] ?? raiseShot(shot)
            nest.position = spot(shot.x, shot.y)
            nest.zPosition = 60
            nest.zRotation = atan2(CGFloat(-shot.vy), CGFloat(shot.vx))
        }
        for (tag, nest) in tracer where !seen.contains(tag) {
            tracer.removeValue(forKey: tag)
            nest.removeFromParent()
        }
    }

    private func raiseShot(_ shot: ShotView) -> SKNode {
        let tint = shot.mine ? Hide.gild : Hide.ember
        let nest = SKShapeNode(
            rect: CGRect(x: -22 * grain, y: -7 * grain, width: 44 * grain, height: 14 * grain),
            cornerRadius: 7 * grain
        )
        nest.fillColor = tint
        nest.strokeColor = Hide.parchment.withAlphaComponent(0.8)
        nest.lineWidth = 1
        nest.glowWidth = 4
        flying.addChild(nest)
        tracer[shot.tag] = nest
        return nest
    }

    private func dressLoose(_ room: RoomView) {
        var seen = Set<UInt32>()
        for mote in room.motes {
            seen.insert(mote.tag)
            let nest = loose[mote.tag] ?? raiseMote(mote)
            nest.position = spot(mote.x, mote.y)
            nest.zPosition = rank(mote.y, 1)
        }
        for (tag, nest) in loose where !seen.contains(tag) {
            loose.removeValue(forKey: tag)
            nest.run(.sequence([
                .group([
                    .moveBy(x: 0, y: 26, duration: 0.2),
                    .fadeOut(withDuration: 0.2),
                ]),
                .removeFromParent(),
            ]))
        }
    }

    private func raiseMote(_ mote: MoteView) -> SKNode {
        let nest = SKNode()
        let reach: CGFloat = mote.kind == Pickup.chest ? 120 : 64
        if let art = Relief.mote(mote.kind) {
            let piece = carving(art, reach * grain)
            nest.addChild(piece)
        }
        if mote.kind == Pickup.coin {
            nest.run(.repeatForever(.sequence([
                .moveBy(x: 0, y: 5, duration: 0.5),
                .moveBy(x: 0, y: -5, duration: 0.5),
            ])))
        } else {
            let glow = SKShapeNode(circleOfRadius: reach * grain * 0.5)
            glow.fillColor = Hide.lapis.withAlphaComponent(0.14)
            glow.strokeColor = .clear
            glow.zPosition = -1
            glow.run(.repeatForever(.sequence([
                .scale(to: 1.15, duration: 0.8),
                .scale(to: 0.9, duration: 0.8),
            ])))
            nest.addChild(glow)
        }
        litter.addChild(nest)
        loose[mote.tag] = nest
        return nest
    }

    // --- the frame ---------------------------------------------------------

    func show(_ room: RoomView) {
        latest = room
        span = CGSize(width: CGFloat(room.spanX), height: CGFloat(room.spanY))
        measure()
        let cut = room.stones.reduce(room.stones.count &* 7919) { tally, stone in
            tally &* 31 &+ Int(stone.x) &* 7 &+ Int(stone.y) &* 13 &+ Int(stone.girth)
        }
        if !laid || cut != mason {
            laid = true
            mason = cut
            spill.removeAll()
            layFloor()
            layStones(room)
            raiseWalker()
        }
        layGate(room)

        raiseWalker()
        walker?.position = spot(room.heroX, room.heroY)
        walker?.zPosition = rank(room.heroY, 4)
        turn(room)
        sway(room.drunk)
        walkerShell?.alpha = room.sheltered ? 0.55 : 1
        halo?.strokeColor = room.drunk
            ? Hide.ember
            : room.dashing
                ? Hide.lapis
                : Hide.gild.withAlphaComponent(0.7)
        if room.shield > 0 {
            halo?.fillColor = Hide.lapis.withAlphaComponent(0.3)
        } else {
            halo?.fillColor = Hide.gild.withAlphaComponent(0.16)
        }

        dressCrowd(room)
        dressShots(room)
        dressLoose(room)
        for flash in room.flashes { burst(flash) }
    }

    // --- what the eye is told ----------------------------------------------

    private func burst(_ flash: FlashView) {
        let at = spot(flash.x, flash.y)
        switch flash.kind {
        case Omen.swing:
            let arc = SKShapeNode(circleOfRadius: 54 * grain)
            arc.position = at
            arc.fillColor = .clear
            arc.strokeColor = Hide.parchment
            arc.lineWidth = 4
            arc.zPosition = 71
            arc.run(.sequence([
                .group([.scale(to: 1.5, duration: 0.14), .fadeOut(withDuration: 0.14)]),
                .removeFromParent(),
            ]))
            sparks.addChild(arc)
        case Omen.bite, Omen.took:
            float("\(flash.value)", at: at, tint: flash.kind == Omen.took ? Hide.ember : Hide.parchment)
            spray(at, drops: 5 + Int(min(6, flash.value)), reach: 40)
            if flash.kind == Omen.took { welt() }
        case Omen.slay:
            ring(at, tint: Hide.ember, reach: flash.value > 0 ? 220 : 110)
            spray(at, drops: flash.value > 0 ? 26 : 14, reach: flash.value > 0 ? 120 : 70)
            for _ in 0..<(flash.value > 0 ? 3 : 1) {
                stain(at, reach: CGFloat(60 + Int(arc4random_uniform(70))))
            }
        case Omen.swill:
            froth(at)
        case Omen.coin:
            float("+\(max(1, flash.value) * 2)", at: at, tint: Hide.gild)
        case Omen.mend:
            ring(at, tint: Hide.verdure, reach: 90)
        case Omen.boom:
            ring(at, tint: Hide.ember, reach: CGFloat(max(60, flash.value)))
        case Omen.cast:
            ring(at, tint: Hide.lapis, reach: 140)
        case Omen.hatch:
            ring(at, tint: Hide.bruise, reach: 90)
        default:
            break
        }
    }

    // --- blood -------------------------------------------------------------
    //
    // Wounds are drawn, and what comes out of a body stays on the floor for
    // the rest of the chamber. The switch in Settings turns all of it off and
    // changes nothing else: the fight is decided in the core either way.

    private func spray(_ at: CGPoint, drops: Int, reach: CGFloat) {
        guard Deck.shared.goreOn else { return }
        for _ in 0..<drops {
            let bead = SKShapeNode(ellipseOf: CGSize(
                width: CGFloat(3 + arc4random_uniform(6)) * grain * 1.6,
                height: CGFloat(3 + arc4random_uniform(5)) * grain * 1.6
            ))
            bead.position = at
            bead.fillColor = Hide.gore(Int(arc4random_uniform(2)))
            bead.strokeColor = .clear
            bead.zPosition = 73
            sparks.addChild(bead)
            let lean = CGFloat(arc4random_uniform(628)) / 100
            let fling = reach * grain * CGFloat(40 + arc4random_uniform(100)) / 100
            bead.run(.sequence([
                .group([
                    .move(by: CGVector(dx: cos(lean) * fling, dy: sin(lean) * fling), duration: 0.26),
                    .scale(to: 0.4, duration: 0.26),
                    .sequence([.wait(forDuration: 0.16), .fadeOut(withDuration: 0.1)]),
                ]),
                .removeFromParent(),
            ]))
        }
    }

    /// A stain, which is not an effect: it is laid into the floor layer and
    /// left there, so a hard chamber looks like one by the end. Drawn as a
    /// cluster of overlapping blots multiplied into the stone, because one
    /// clean oval reads as a sticker and not as something that was spilled.
    private func stain(_ at: CGPoint, reach: CGFloat) {
        guard Deck.shared.goreOn else { return }
        let patch = SKNode()
        patch.position = at
        patch.zPosition = CGFloat(21 + spill.count % 4)
        for blot in 0..<(4 + Int(arc4random_uniform(3))) {
            let fade = blot == 0 ? CGFloat(1) : CGFloat(50 + arc4random_uniform(40)) / 100
            let wide = reach * grain * fade * CGFloat(50 + arc4random_uniform(50)) / 100
            let drop = SKShapeNode(ellipseOf: CGSize(
                width: wide,
                height: wide * CGFloat(45 + arc4random_uniform(45)) / 100
            ))
            drop.position = CGPoint(
                x: CGFloat(arc4random_uniform(UInt32(max(2, reach)))) * grain - reach * grain / 2,
                y: CGFloat(arc4random_uniform(UInt32(max(2, reach / 2)))) * grain - reach * grain / 4
            )
            drop.zRotation = CGFloat(arc4random_uniform(628)) / 100
            drop.fillColor = Hide.gore(blot == 0 ? 0 : 1).withAlphaComponent(0.42)
            drop.strokeColor = .clear
            drop.blendMode = .multiply
            patch.addChild(drop)
        }
        patch.setScale(0.3)
        patch.run(.scale(to: 1, duration: 0.2))
        litter.addChild(patch)
        spill.append(patch)
        // A floor can only hold so much before it turns into one red sheet.
        while spill.count > 40 {
            spill.removeFirst().run(.sequence([.fadeOut(withDuration: 0.5), .removeFromParent()]))
        }
    }

    /// Blood that was already here. Same shape as a fresh stain, drier and
    /// flatter, drawn into the floor before the fight starts.
    private func oldBlood(_ at: CGPoint, reach: CGFloat) {
        guard let art = Relief.scarlet(Int(arc4random_uniform(4))) else { return }
        let dried = carving(art, reach * 2.6 * grain)
        dried.position = at
        dried.zPosition = 1
        dried.alpha = 0.9
        dried.zRotation = CGFloat(arc4random_uniform(628)) / 100
        dried.color = Hide.pitch
        dried.colorBlendFactor = 0.22
        shade.addChild(dried)
    }

    /// What the player sees when it is their own blood: the glass takes it.
    private func welt() {
        guard Deck.shared.goreOn else { return }
        let smear = SKShapeNode(rect: CGRect(origin: .zero, size: size))
        smear.fillColor = Hide.gore(2).withAlphaComponent(0.26)
        smear.strokeColor = .clear
        smear.zPosition = 80
        smear.run(.sequence([.fadeOut(withDuration: 0.34), .removeFromParent()]))
        sparks.addChild(smear)
    }

    /// What the hero says out loud. Shown over her head, because a line nobody
    /// reads is a line nobody wrote.
    func bark(_ line: String) {
        guard let nest = walker else { return }
        nest.childNode(withName: Mark.bark)?.removeFromParent()
        let said = SKLabelNode(text: line)
        said.name = Mark.bark
        said.fontName = "Georgia-Bold"
        said.fontSize = 42 * grain
        said.fontColor = Hide.parchment
        said.position = CGPoint(x: 0, y: 150 * grain)
        said.zPosition = 9
        said.run(.sequence([
            .wait(forDuration: 0.9),
            .fadeOut(withDuration: 0.3),
            .removeFromParent(),
        ]))
        nest.addChild(said)
    }

    /// The jar going down: a head of foam thrown off her, and a warm ring
    /// that tells the player the next six seconds are not the usual ones.
    private func froth(_ at: CGPoint) {
        // The jar itself, lifted, tipped back and tossed aside.
        if let art = Relief.brew {
            let jar = carving(art, 120 * grain)
            jar.position = CGPoint(x: at.x + 26 * grain, y: at.y + 60 * grain)
            jar.zPosition = 75
            jar.run(.sequence([
                .group([
                    .moveBy(x: -14 * grain, y: 46 * grain, duration: 0.3),
                    .rotate(toAngle: -0.9, duration: 0.5),
                ]),
                .wait(forDuration: 0.2),
                .group([
                    .moveBy(x: 50 * grain, y: -40 * grain, duration: 0.3),
                    .fadeOut(withDuration: 0.3),
                    .rotate(toAngle: -2.4, duration: 0.3),
                ]),
                .removeFromParent(),
            ]))
            sparks.addChild(jar)
        }
        for _ in 0..<18 {
            let blot = SKShapeNode(circleOfRadius: CGFloat(3 + Int(arc4random_uniform(5))) * grain)
            blot.position = at
            blot.fillColor = Hide.parchment
            blot.strokeColor = .clear
            blot.zPosition = 74
            let swing = CGFloat(Int(arc4random_uniform(160)) - 80) * grain
            let lift = CGFloat(Int(arc4random_uniform(130)) + 20) * grain
            blot.run(.sequence([
                .group([
                    .moveBy(x: swing, y: lift, duration: 0.42),
                    .fadeOut(withDuration: 0.42),
                    .scale(to: 0.4, duration: 0.42),
                ]),
                .removeFromParent(),
            ]))
            sparks.addChild(blot)
        }
        ring(at, tint: Hide.gild, reach: 170)
    }

    /// While the beer lasts she cannot stand still: the sprite rolls a little
    /// and the ring under her burns warmer, so the state is readable even with
    /// a thumb over the health bar.
    private func sway(_ on: Bool) {
        guard on != tipsy else { return }
        tipsy = on
        guard let shell = walkerShell else { return }
        shell.removeAction(forKey: Mark.sway)
        guard on else {
            shell.zRotation = 0
            return
        }
        shell.run(.repeatForever(.sequence([
            .rotate(toAngle: 0.07, duration: 0.42),
            .rotate(toAngle: -0.07, duration: 0.42),
        ])), withKey: Mark.sway)
    }

    private func ring(_ at: CGPoint, tint: SKColor, reach: CGFloat) {
        let hoop = SKShapeNode(circleOfRadius: reach * grain * 0.5)
        hoop.position = at
        hoop.fillColor = tint.withAlphaComponent(0.18)
        hoop.strokeColor = tint
        hoop.lineWidth = 3
        hoop.zPosition = 71
        hoop.setScale(0.4)
        hoop.run(.sequence([
            .group([.scale(to: 1.2, duration: 0.24), .fadeOut(withDuration: 0.24)]),
            .removeFromParent(),
        ]))
        sparks.addChild(hoop)
    }

    private func float(_ text: String, at: CGPoint, tint: SKColor) {
        let mark = SKLabelNode(text: text)
        mark.fontName = "Menlo-Bold"
        mark.fontSize = 48 * grain
        mark.fontColor = tint
        mark.position = at
        mark.zPosition = 72
        mark.run(.sequence([
            .group([
                .moveBy(x: 0, y: 70 * grain, duration: 0.5),
                .fadeOut(withDuration: 0.5),
            ]),
            .removeFromParent(),
        ]))
        sparks.addChild(mark)
    }

    // --- the thumb ---------------------------------------------------------

    override func update(_ currentTime: TimeInterval) {
        if last == 0 { last = currentTime }
        let gap = min(0.1, currentTime - last)
        last = currentTime
        var push = (0, 0)
        #if DEBUG
        if rehearsing, let room = latest {
            let want: (Int32, Int32)? = room.brood
                .min(by: {
                    abs($0.x - room.heroX) + abs($0.y - room.heroY)
                        < abs($1.x - room.heroX) + abs($1.y - room.heroY)
                })
                .map { ($0.x, $0.y) }
                ?? (room.portalOpen ? (room.portalX, room.portalY) : nil)
            if let want {
                var dx = Int(want.0 - room.heroX)
                var dy = Int(want.1 - room.heroY)
                if abs(dx) + abs(dy) < 8 { stalled += 1 } else { stalled = 0 }
                if stalled > 30 {
                    let swing = dy
                    dy = -dx
                    dx = swing
                }
                let reach = max(1, abs(dx) + abs(dy))
                push = (dx * 1000 / reach, dy * 1000 / reach)
            }
            onPulse?(push.0, push.1, UInt32(gap * 1000))
            return
        }
        #endif
        onPulse?(push.0, push.1, UInt32(gap * 1000))
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard size.width > 1 else { return }
        laid = false
    }

}

/// Node names, kept in one place so a typo cannot quietly break a lookup.
private enum Mark {
    static let shell = "s"
    static let pip = "p"
    static let tell = "t"
    static let bark = "b"
    static let sway = "w"
}

/// The thumb pad. Drawn and handled in UIKit above the fight: a ring parked
/// within reach from the first frame, which jumps under the thumb when the
/// floor is touched and strolls home when it is let go.
///
/// It decides nothing about the fight. It only answers one question, once a
/// frame: which way is the player pushing, and how hard.
final class ReinsPad: UIView {
    private let ring = CAShapeLayer()
    private let bound = CAShapeLayer()
    private let knob = CAShapeLayer()
    private let hint = chisel("", Scribe.plain(12), Hide.parchment.withAlphaComponent(0.85), align: .center)

    private var grip: UITouch?
    private var seat = CGPoint.zero
    private var lean = CGPoint.zero
    private var nudged = false

    private let girth: CGFloat = 64
    private let travel: CGFloat = 60

    /// -1000...1000 per axis, y counted downwards as the world counts it.
    var push: (Int, Int) {
        let reach = sqrt(lean.x * lean.x + lean.y * lean.y)
        guard reach > 4 else { return (0, 0) }
        let pull = min(1, reach / travel)
        return (Int(lean.x / reach * pull * 1000), Int(lean.y / reach * pull * 1000))
    }

    /// The same direction, at full strength, for a knack that needs aiming.
    var aim: (Int, Int) {
        let reach = sqrt(lean.x * lean.x + lean.y * lean.y)
        guard reach > 8 else { return (0, 0) }
        return (Int(lean.x / reach * 1000), Int(lean.y / reach * 1000))
    }

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = true

        ring.fillColor = Hide.pitch.withAlphaComponent(0.26).cgColor
        ring.strokeColor = Hide.parchment.withAlphaComponent(0.36).cgColor
        ring.lineWidth = 2
        bound.fillColor = UIColor.clear.cgColor
        bound.strokeColor = Hide.parchment.withAlphaComponent(0.14).cgColor
        bound.lineWidth = 1
        knob.fillColor = Hide.gild.withAlphaComponent(0.5).cgColor
        knob.strokeColor = Hide.parchment.cgColor
        knob.lineWidth = 2
        for skin in [ring, bound, knob] { layer.addSublayer(skin) }

        hint.text = Vault.say(Lexeme.runTipStick)
        hint.layer.shadowColor = Hide.pitch.cgColor
        hint.layer.shadowOpacity = 0.9
        hint.layer.shadowRadius = 4
        hint.layer.shadowOffset = .zero
        hint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -(girth * 2 + 18)),
            hint.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Grid.gutter),
        ])
        alpha = 0.55
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        seat = berth
        ring.path = UIBezierPath(arcCenter: .zero, radius: girth, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        bound.path = UIBezierPath(arcCenter: .zero, radius: travel, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        knob.path = UIBezierPath(arcCenter: .zero, radius: 24, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        if grip == nil { park() }
    }

    /// Low and to the side of whichever thumb the player said they use.
    private var berth: CGPoint {
        CGPoint(
            x: Deck.shared.handedLeft ? bounds.width - girth - 24 : girth + 24,
            y: bounds.height - girth - 20
        )
    }

    private func park() {
        lean = .zero
        ring.position = seat
        bound.position = seat
        knob.position = seat
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard grip == nil, let touch = touches.first else { return }
        grip = touch
        seat = touch.location(in: self)
        lean = .zero
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.position = seat
        bound.position = seat
        knob.position = seat
        CATransaction.commit()
        alpha = 1
        if !nudged {
            nudged = true
            UIView.animate(withDuration: 0.3) { self.hint.alpha = 0 }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = grip, touches.contains(touch) else { return }
        let at = touch.location(in: self)
        var tilt = CGPoint(x: at.x - seat.x, y: at.y - seat.y)
        let reach = sqrt(tilt.x * tilt.x + tilt.y * tilt.y)
        if reach > travel {
            tilt = CGPoint(x: tilt.x / reach * travel, y: tilt.y / reach * travel)
        }
        lean = tilt
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        knob.position = CGPoint(x: seat.x + tilt.x, y: seat.y + tilt.y)
        CATransaction.commit()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = grip, touches.contains(touch) else { return }
        release()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = grip, touches.contains(touch) else { return }
        release()
    }

    private func release() {
        grip = nil
        seat = berth
        park()
        alpha = 0.55
    }
}
