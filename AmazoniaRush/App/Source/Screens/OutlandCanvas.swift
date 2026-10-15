import SpriteKit

/// The desert above the temple. The player keeps a finger on the sand and the
/// scarab walks there; standing on a dig site opens it. No rules live here —
/// which sites exist and which are buried comes from the core.
final class OutlandCanvas: SKScene {
    /// Fires with the site the scarab is standing on, or nil once it leaves.
    var onReach: ((Int?) -> Void)?

    private struct Waymark {
        var spot: CGPoint
        var badge: SKNode
        var open: Bool
    }

    /// Where each site sits, measured across and down the visible sand.
    private static let anchors: [CGPoint] = [
        CGPoint(x: 0.29, y: 0.80),
        CGPoint(x: 0.69, y: 0.71),
        CGPoint(x: 0.26, y: 0.61),
        CGPoint(x: 0.64, y: 0.51),
        CGPoint(x: 0.29, y: 0.41),
        CGPoint(x: 0.70, y: 0.30),
        CGPoint(x: 0.46, y: 0.19),
    ]

    private let sand = SKSpriteNode()
    private let trail = SKNode()
    private let posts = SKNode()
    private let walker = SKNode()
    private let shell = SKSpriteNode()
    private let shade = SKShapeNode()

    private var marks: [Waymark] = []
    private var atlas: MapView?
    private var footing = 0
    private var goal: CGPoint?
    private var standing: Int?
    private var strideLeft: CGFloat = 0
    private var lastTick: TimeInterval = 0
    private var facing: CGFloat = 1

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = Hide.ink(38, 30, 20)

        sand.texture = Vault.scene(Canvas.aWorldExplorationMapScene).map { SKTexture(image: $0) }
        sand.zPosition = -10
        addChild(sand)

        let dusk = SKSpriteNode(color: Hide.pitch.withAlphaComponent(0.2), size: .zero)
        dusk.name = "dusk"
        dusk.zPosition = -9
        addChild(dusk)

        addChild(trail)
        addChild(posts)

        shade.fillColor = Hide.pitch.withAlphaComponent(0.4)
        shade.strokeColor = .clear
        walker.addChild(shade)
        shell.texture = Relief.shelled
        shell.zPosition = 1
        walker.addChild(shell)
        walker.zPosition = 40
        addChild(walker)
    }

    required init?(coder: NSCoder) { nil }

    // --- laying out the sand ----------------------------------------------

    func settle(_ fresh: MapView, standingAt site: Int) {
        atlas = fresh
        footing = site
        standing = nil
        goal = nil
        rebuild()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        rebuild()
    }

    private func rebuild() {
        guard size.width > 1, let atlas else { return }
        dressSand()

        trail.removeAllChildren()
        posts.removeAllChildren()
        marks = []

        for (index, region) in atlas.regions.enumerated() {
            let anchor = OutlandCanvas.anchors[index % OutlandCanvas.anchors.count]
            let spot = CGPoint(x: anchor.x * size.width, y: (1 - anchor.y) * size.height)
            let badge = post(region, index, at: spot)
            posts.addChild(badge)
            marks.append(Waymark(spot: spot, badge: badge, open: region.open))
        }

        for step in 1..<max(1, marks.count) {
            paveTrail(from: marks[step - 1], to: marks[step])
        }

        let reach = min(size.width, size.height) * 0.055
        shade.path = CGPath(
            ellipseIn: CGRect(x: -reach, y: -reach * 0.5, width: reach * 2, height: reach * 0.8),
            transform: nil
        )
        if let span = shell.texture?.size() {
            let scale = reach * 2.6 / max(span.width, span.height)
            shell.size = CGSize(width: span.width * scale, height: span.height * scale)
            shell.position = CGPoint(x: 0, y: reach * 0.45)
        }
        strideLeft = reach

        // The sand is only measured once the view has a size, so the scarab
        // takes its post here rather than when the frame arrived.
        let post = marks.indices.contains(footing) ? footing : 0
        if goal == nil, marks.indices.contains(post) {
            walker.position = marks[post].spot
            standing = nil
            settleStanding()
        }
    }

    private func dressSand() {
        guard let art = sand.texture else { return }
        let span = art.size()
        let fill = max(size.width / span.width, size.height / span.height)
        sand.size = CGSize(width: span.width * fill, height: span.height * fill)
        sand.position = CGPoint(x: size.width / 2, y: size.height / 2)
        if let dusk = childNode(withName: "dusk") as? SKSpriteNode {
            dusk.size = size
            dusk.position = sand.position
        }
    }

    /// A caravan track of hoofprints between two sites, faded when the far
    /// end is still buried.
    private func paveTrail(from: Waymark, to: Waymark) {
        let steps = 11
        for step in 1..<steps {
            let share = CGFloat(step) / CGFloat(steps)
            let dot = SKShapeNode(circleOfRadius: max(1.6, size.width * 0.006))
            dot.position = CGPoint(
                x: from.spot.x + (to.spot.x - from.spot.x) * share,
                y: from.spot.y + (to.spot.y - from.spot.y) * share
            )
            dot.fillColor = (to.open ? Hide.gild : Hide.hush).withAlphaComponent(to.open ? 0.5 : 0.22)
            dot.strokeColor = .clear
            dot.zPosition = -1
            trail.addChild(dot)
        }
    }

    private func post(_ region: MapRegionView, _ index: Int, at spot: CGPoint) -> SKNode {
        let reach = min(size.width, size.height) * 0.11
        let stand = SKNode()
        // The landmark sits a little behind its spot, leaving the sand in
        // front of it clear for the scarab to stand on.
        stand.position = CGPoint(x: spot.x, y: spot.y + reach * 0.42)
        stand.zPosition = 10 + CGFloat(index) * 0.01

        let ring = SKShapeNode(ellipseIn: CGRect(
            x: -reach * 0.62, y: -reach * 0.36, width: reach * 1.24, height: reach * 0.62
        ))
        ring.fillColor = (region.open ? Hide.brass : Hide.hush).withAlphaComponent(0.18)
        ring.strokeColor = (region.open ? Hide.gild : Hide.hush).withAlphaComponent(0.8)
        ring.lineWidth = 2
        stand.addChild(ring)

        if let art = Relief.waymark(index) {
            let span = art.size()
            let scale = reach * 1.7 / max(span.width, span.height)
            let piece = SKSpriteNode(texture: art)
            piece.size = CGSize(width: span.width * scale, height: span.height * scale)
            piece.position = CGPoint(x: 0, y: piece.size.height * 0.4)
            piece.alpha = region.open ? 1 : 0.8
            if !region.open {
                piece.color = Hide.pitch
                piece.colorBlendFactor = 0.55
            }
            stand.addChild(piece)
        }

        let plaque = SKLabelNode(text: Vault.say(region.name))
        plaque.fontName = "Menlo-Bold"
        plaque.fontSize = max(9, reach * 0.3)
        plaque.fontColor = region.open ? Hide.parchment : Hide.hush
        plaque.verticalAlignmentMode = .center
        let perch = reach * 1.5
        plaque.position = CGPoint(x: 0, y: perch)
        let board = SKShapeNode(
            rect: CGRect(
                x: -plaque.frame.width / 2 - 6, y: perch - plaque.frame.height / 2 - 3,
                width: plaque.frame.width + 12, height: plaque.frame.height + 6
            ),
            cornerRadius: 5
        )
        board.fillColor = Hide.pitch.withAlphaComponent(0.72)
        board.strokeColor = (region.open ? Hide.brassDim : Hide.hush).withAlphaComponent(0.7)
        board.lineWidth = 1
        stand.addChild(board)
        stand.addChild(plaque)

        if region.open, region.cleared < region.nodeSpan {
            let beacon = SKShapeNode(circleOfRadius: reach * 0.12)
            beacon.position = CGPoint(x: reach * 0.52, y: reach * 0.1)
            beacon.fillColor = Hide.ember
            beacon.strokeColor = .clear
            beacon.run(.repeatForever(.sequence([
                .fadeAlpha(to: 0.25, duration: 0.8),
                .fadeAlpha(to: 1, duration: 0.8),
            ])))
            stand.addChild(beacon)
        }
        return stand
    }

    // --- walking -----------------------------------------------------------

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        steer(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        steer(touches)
    }

    private func steer(_ touches: Set<UITouch>) {
        guard let spot = touches.first?.location(in: self) else { return }
        // A touch near a site walks right up to it; anywhere else is free sand.
        if let near = marks.enumerated().min(by: {
            hypot($0.element.spot.x - spot.x, $0.element.spot.y - spot.y)
                < hypot($1.element.spot.x - spot.x, $1.element.spot.y - spot.y)
        }), hypot(near.element.spot.x - spot.x, near.element.spot.y - spot.y) < strideLeft * 1.6 {
            goal = near.element.spot
        } else {
            goal = CGPoint(
                x: min(max(spot.x, strideLeft), size.width - strideLeft),
                y: min(max(spot.y, strideLeft), size.height - strideLeft)
            )
        }
    }

    override func update(_ currentTime: TimeInterval) {
        let slice = lastTick == 0 ? 1 / 60 : min(0.05, currentTime - lastTick)
        lastTick = currentTime
        guard let goal else {
            bob(false)
            return
        }
        let dx = goal.x - walker.position.x
        let dy = goal.y - walker.position.y
        let gap = hypot(dx, dy)
        if gap < 1.5 {
            self.goal = nil
            bob(false)
            settleStanding()
            return
        }
        let pace = min(size.width, size.height) * 0.52 * CGFloat(slice)
        let travel = min(pace, gap)
        walker.position = CGPoint(
            x: walker.position.x + dx / gap * travel,
            y: walker.position.y + dy / gap * travel
        )
        let wanted: CGFloat = dx < -0.5 ? -1 : (dx > 0.5 ? 1 : facing)
        if wanted != facing {
            facing = wanted
            shell.xScale = facing
        }
        bob(true)
        settleStanding()
        puff()
    }

    private func bob(_ moving: Bool) {
        if moving, walker.action(forKey: "gait") == nil {
            walker.run(.repeatForever(.sequence([
                .rotate(toAngle: 0.06, duration: 0.12),
                .rotate(toAngle: -0.06, duration: 0.12),
            ])), withKey: "gait")
        } else if !moving, walker.action(forKey: "gait") != nil {
            walker.removeAction(forKey: "gait")
            walker.run(.rotate(toAngle: 0, duration: 0.1))
        }
    }

    private var puffClock: CGFloat = 0

    private func puff() {
        puffClock += 1
        guard puffClock > 7, let dust = Relief.dustPuff else { return }
        puffClock = 0
        let span = dust.size()
        let reach = strideLeft * 1.2
        let scale = reach / max(span.width, span.height)
        let grain = SKSpriteNode(texture: dust)
        grain.size = CGSize(width: span.width * scale, height: span.height * scale)
        grain.position = CGPoint(x: walker.position.x, y: walker.position.y - strideLeft * 0.2)
        grain.zPosition = 35
        grain.alpha = 0.5
        addChild(grain)
        grain.run(.sequence([
            .group([.fadeOut(withDuration: 0.5), .scale(to: 1.4, duration: 0.5)]),
            .removeFromParent(),
        ]))
    }

    /// Tells the stage which site the scarab is close enough to open.
    private func settleStanding() {
        let hit = marks.enumerated().first {
            hypot($0.element.spot.x - walker.position.x, $0.element.spot.y - walker.position.y)
                < strideLeft * 1.5
        }?.offset
        guard hit != standing else { return }
        standing = hit
        for (index, mark) in marks.enumerated() {
            mark.badge.run(.scale(to: index == hit ? 1.12 : 1, duration: 0.16))
        }
        onReach?(hit)
    }

#if DEBUG
    /// Walks to a site without a finger on the glass, which is the only way
    /// the headless screenshot pass can show the scarab in motion.
    func rehearse(_ site: Int) {
        guard marks.indices.contains(site) else { return }
        goal = marks[site].spot
    }
#endif
}
