import Foundation

// The descent frame, read in exactly the order `Delve::inscribe` writes it.
// Nothing here decides anything: the rules all live in the native core.

/// Beast kinds. Mirrors `delve::brood`.
enum Breed {
    static let husk: UInt8 = 0
    static let jackal: UInt8 = 1
    static let spitter: UInt8 = 2
    static let hopper: UInt8 = 3
    static let warden: UInt8 = 4
    static let brooder: UInt8 = 5
    static let sentinel: UInt8 = 6
    static let revenant: UInt8 = 7
    static let kinds = 8
}

/// What a body is busy doing. Mirrors `arena::mood`.
enum Mood {
    static let walk: UInt8 = 0
    static let wind: UInt8 = 1
    static let lunge: UInt8 = 2
    static let hurt: UInt8 = 3
}

/// Loose things on the floor. Mirrors `arena::trove`.
enum Pickup {
    static let coin: UInt8 = 0
    static let heart: UInt8 = 1
    static let focus: UInt8 = 2
    static let relic: UInt8 = 3
    static let chest: UInt8 = 4
}

/// One-frame events the view layer turns into motion and sound.
/// Mirrors `arena::spark`.
enum Omen {
    static let swing: UInt8 = 0
    static let bite: UInt8 = 1
    static let slay: UInt8 = 2
    static let took: UInt8 = 3
    static let coin: UInt8 = 4
    static let mend: UInt8 = 5
    static let cast: UInt8 = 6
    static let boom: UInt8 = 7
    static let hatch: UInt8 = 8
    static let swill: UInt8 = 9
}

/// Chamber goals. Mirrors `delve::goal`.
enum Errand {
    static let cull: UInt8 = 0
    static let flee: UInt8 = 1
    static let endure: UInt8 = 2
    static let press: UInt8 = 3
    static let hoard: UInt8 = 4
    static let crown: UInt8 = 5
}

/// Where the run currently sits. Mirrors `expedition::stride`.
enum Leg {
    static let fight: UInt8 = 0
    static let card: UInt8 = 1
    static let cache: UInt8 = 2
    static let fork: UInt8 = 3
    static let haven: UInt8 = 4
    static let crowned: UInt8 = 5
    static let fallen: UInt8 = 6
}

/// Room flavours on the branch map. Mirrors `expedition::lair`.
enum Haunt {
    static let skirmish: UInt8 = 0
    static let elite: UInt8 = 1
    static let snare: UInt8 = 2
    static let trove: UInt8 = 3
    static let swarm: UInt8 = 4
    static let siege: UInt8 = 5
    static let camp: UInt8 = 6
    static let trader: UInt8 = 7
    static let crown: UInt8 = 8
    static let kinds = 9
}

/// A pillar on the floor: bodies walk around it, shots break on it.
struct StoneView {
    var x: Int32 = 0
    var y: Int32 = 0
    var girth: Int32 = 60
    var look: UInt8 = 0
}

struct BeastView {
    var tag: UInt32 = 0
    var breed: UInt8 = 0
    var x: Int32 = 0
    var y: Int32 = 0
    var hp: Int32 = 1
    var cap: Int32 = 1
    var girth: Int32 = 32
    var mood: UInt8 = Mood.walk
    var lookX: Int32 = 0
    var lookY: Int32 = 1000
    var boss = false

    var share: Float { min(1, max(0, Float(hp) / Float(max(1, cap)))) }
}

struct ShotView {
    var tag: UInt32 = 0
    var x: Int32 = 0
    var y: Int32 = 0
    var vx: Int32 = 0
    var vy: Int32 = 0
    var mine = false
}

struct MoteView {
    var tag: UInt32 = 0
    var kind: UInt8 = Pickup.coin
    var x: Int32 = 0
    var y: Int32 = 0
}

struct FlashView {
    var kind: UInt8 = 0
    var x: Int32 = 0
    var y: Int32 = 0
    var value: Int32 = 0
}

/// One frame of the fight, in world units. The drawing side scales these to
/// whatever glass it has; the core never learns a pixel.
struct RoomView {
    var spanX: Int32 = 1000
    var spanY: Int32 = 1600
    var goal: UInt8 = Errand.cull
    var wave: UInt32 = 0
    var waves: UInt32 = 1
    var foesLeft: UInt32 = 0
    var coins: UInt32 = 0
    var turn: UInt32 = 0
    var hold: UInt32 = 0
    var portalOpen = false
    var portalX: Int32 = 0
    var portalY: Int32 = 0
    var flawless = true

    var heroX: Int32 = 0
    var heroY: Int32 = 0
    var hp: Int32 = 1
    var hpCap: Int32 = 1
    var shield: Int32 = 0
    var focus: Int32 = 0
    var focusCap: Int32 = 1
    var lookX: Int32 = 0
    var lookY: Int32 = 1000
    var dashing = false
    var sheltered = false
    /// The temple beer is still talking: she hits harder and steers worse.
    var drunk = false

    var stones: [StoneView] = []
    var brood: [BeastView] = []
    var shots: [ShotView] = []
    var motes: [MoteView] = []
    var flashes: [FlashView] = []

    init(_ scroll: inout Scroll) {
        spanX = Int32(scroll.quad())
        spanY = Int32(scroll.quad())
        goal = scroll.byte()
        wave = scroll.quad()
        waves = max(1, scroll.quad())
        foesLeft = scroll.quad()
        coins = scroll.quad()
        turn = scroll.quad()
        hold = scroll.quad()
        portalOpen = scroll.flag()
        portalX = scroll.signed()
        portalY = scroll.signed()
        flawless = scroll.flag()

        heroX = scroll.signed()
        heroY = scroll.signed()
        hp = scroll.signed()
        hpCap = max(1, scroll.signed())
        shield = scroll.signed()
        focus = scroll.signed()
        focusCap = max(1, scroll.signed())
        lookX = scroll.signed()
        lookY = scroll.signed()
        dashing = scroll.flag()
        sheltered = scroll.flag()
        drunk = scroll.flag()

        let stoneSpan = scroll.tally()
        stones.reserveCapacity(stoneSpan)
        for _ in 0..<stoneSpan {
            var stone = StoneView()
            stone.x = scroll.signed()
            stone.y = scroll.signed()
            stone.girth = scroll.signed()
            stone.look = scroll.byte()
            stones.append(stone)
        }

        let broodSpan = scroll.tally()
        brood.reserveCapacity(broodSpan)
        for _ in 0..<broodSpan {
            var beast = BeastView()
            beast.tag = scroll.quad()
            beast.breed = scroll.byte()
            beast.x = scroll.signed()
            beast.y = scroll.signed()
            beast.hp = scroll.signed()
            beast.cap = max(1, scroll.signed())
            beast.girth = scroll.signed()
            beast.mood = scroll.byte()
            beast.lookX = scroll.signed()
            beast.lookY = scroll.signed()
            beast.boss = scroll.flag()
            brood.append(beast)
        }

        let shotSpan = scroll.tally()
        shots.reserveCapacity(shotSpan)
        for _ in 0..<shotSpan {
            var shot = ShotView()
            shot.tag = scroll.quad()
            shot.x = scroll.signed()
            shot.y = scroll.signed()
            shot.vx = scroll.signed()
            shot.vy = scroll.signed()
            shot.mine = scroll.flag()
            shots.append(shot)
        }

        let moteSpan = scroll.tally()
        motes.reserveCapacity(moteSpan)
        for _ in 0..<moteSpan {
            var mote = MoteView()
            mote.tag = scroll.quad()
            mote.kind = scroll.byte()
            mote.x = scroll.signed()
            mote.y = scroll.signed()
            motes.append(mote)
        }

        let flashSpan = scroll.tally()
        flashes.reserveCapacity(flashSpan)
        for _ in 0..<flashSpan {
            var flash = FlashView()
            flash.kind = scroll.byte()
            flash.x = scroll.signed()
            flash.y = scroll.signed()
            flash.value = scroll.signed()
            flashes.append(flash)
        }
    }

    var lifeShare: Float { min(1, max(0, Float(hp) / Float(max(1, hpCap)))) }
    var waveShare: Float { min(1, Float(wave) / Float(max(1, waves))) }
    /// Seconds still to hold out in a chamber that asks for time, not bodies.
    var holdLeft: UInt32 { hold }
}

struct SpoilsView {
    var shards: UInt64 = 0
    var cores: UInt64 = 0
    var resin: UInt64 = 0
    var seals: UInt64 = 0
    var light: UInt64 = 0
    var relic: Int32 = -1
    var medals: UInt32 = 0
}

struct StopView {
    var kind: UInt8 = 0
    var real = false
    var done = false
    var here = false
    var open = false
    var name: UInt16 = 0
    var blurb: UInt16 = 0
}

struct BoonView {
    var kind: UInt32 = 0
    var name: UInt16 = 0
    var blurb: UInt16 = 0
}

struct WareView {
    var kind: UInt32 = 0
    var name: UInt16 = 0
    var blurb: UInt16 = 0
    var toll: UInt64 = 0
    var affordable = false
}

struct PowerSeatView {
    var power: Int32 = -1
    var name: UInt16 = 0
    var blurb: UInt16 = 0
    var toll: Int32 = 0
    var rest: UInt32 = 0
    var ceiling: UInt32 = 1
    var ready = false

    var filled: Bool { power >= 0 }
    var share: Float {
        guard filled else { return 0 }
        return 1 - min(1, Float(rest) / Float(max(1, ceiling)))
    }
}

struct DelveView {
    var live = false
    var leg: UInt8 = Leg.fallen
    var region: UInt32 = 0
    var node: UInt32 = 0
    var depth: UInt32 = 0
    var rows: UInt32 = 1
    var lane: UInt32 = 0
    var roomsCleared: UInt32 = 0
    var bestMastery: UInt32 = 0
    var lastMastery: UInt32 = 0
    var lastShards: UInt64 = 0
    var flawlessRun = true

    var hp: Int32 = 1
    var hpCap: Int32 = 1
    var vigor: Int32 = 0
    var vigorCap: Int32 = 1

    var spoils = SpoilsView()
    /// Row-major branch map: `map[row][lane]`.
    var map: [[StopView]] = []
    var boons: [BoonView] = []
    var cache: [BoonView] = []
    var wares: [WareView] = []
    var seats: [PowerSeatView] = []

    var haunt: UInt8 = 0
    var hauntLine: UInt16 = 0
    var goalLine: UInt16 = 0
    var goalHint: UInt16 = 0
    var room: RoomView?

    var purse = Purse()
    var attunement: UInt32 = 0
    var tutorStep: UInt32 = 0
    var switches: UInt32 = 0
    var skinWorn: UInt32 = 0

    /// An empty descent, so a screen can hold a shape before its first read.
    init() {}

    init(_ scroll: inout Scroll) {
        live = scroll.flag()
        if live {
            leg = scroll.byte()
            region = scroll.quad()
            node = scroll.quad()
            depth = scroll.quad()
            rows = max(1, scroll.quad())
            lane = scroll.quad()
            roomsCleared = scroll.quad()
            bestMastery = scroll.quad()
            lastMastery = scroll.quad()
            lastShards = scroll.octet()
            flawlessRun = scroll.flag()

            hp = scroll.signed()
            hpCap = max(1, scroll.signed())
            vigor = scroll.signed()
            vigorCap = max(1, scroll.signed())

            spoils.shards = scroll.octet()
            spoils.cores = scroll.octet()
            spoils.resin = scroll.octet()
            spoils.seals = scroll.octet()
            spoils.light = scroll.octet()
            spoils.relic = scroll.signed()
            spoils.medals = scroll.quad()

            let rowSpan = scroll.tally()
            map.reserveCapacity(rowSpan)
            for _ in 0..<rowSpan {
                let laneSpan = scroll.tally()
                var line: [StopView] = []
                line.reserveCapacity(laneSpan)
                for _ in 0..<laneSpan {
                    var stop = StopView()
                    stop.kind = scroll.byte()
                    stop.real = scroll.flag()
                    stop.done = scroll.flag()
                    stop.here = scroll.flag()
                    stop.open = scroll.flag()
                    stop.name = scroll.pair()
                    stop.blurb = scroll.pair()
                    line.append(stop)
                }
                map.append(line)
            }

            func readBoons() -> [BoonView] {
                let span = scroll.tally()
                var batch: [BoonView] = []
                batch.reserveCapacity(span)
                for _ in 0..<span {
                    var boon = BoonView()
                    boon.kind = scroll.quad()
                    boon.name = scroll.pair()
                    boon.blurb = scroll.pair()
                    batch.append(boon)
                }
                return batch
            }
            boons = readBoons()
            cache = readBoons()

            let wareSpan = scroll.tally()
            for _ in 0..<wareSpan {
                var ware = WareView()
                ware.kind = scroll.quad()
                ware.name = scroll.pair()
                ware.blurb = scroll.pair()
                ware.toll = scroll.octet()
                ware.affordable = scroll.flag()
                wares.append(ware)
            }

            let seatSpan = scroll.tally()
            for _ in 0..<seatSpan {
                var seat = PowerSeatView()
                seat.power = scroll.signed()
                seat.name = scroll.pair()
                seat.blurb = scroll.pair()
                seat.toll = scroll.signed()
                seat.rest = scroll.quad()
                seat.ceiling = max(1, scroll.quad())
                seat.ready = scroll.flag()
                seats.append(seat)
            }

            haunt = scroll.byte()
            hauntLine = scroll.pair()
            goalLine = scroll.pair()
            goalHint = scroll.pair()
            room = RoomView(&scroll)
        }
        purse = scroll.purse()
        attunement = scroll.quad()
        tutorStep = scroll.quad()
        switches = scroll.quad()
        skinWorn = scroll.quad()
    }

    var over: Bool { leg == Leg.crowned || leg == Leg.fallen }
    var won: Bool { leg == Leg.crowned }
}
