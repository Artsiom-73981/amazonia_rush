import Foundation

// Typed views over the oracle's frames. Each initialiser reads the stream in
// exactly the order the native side wrote it; nothing here decides anything.

struct HubView {
    var purse = Purse()
    var attunement: UInt32 = 0
    var light: UInt64 = 0
    var lightFloor: UInt64 = 0
    var lightCeiling: UInt64 = 1
    var reawakenings: UInt32 = 0
    var dominion: Float = 1
    var switches: UInt32 = 0
    var tutorStep: UInt32 = 0
    var skinWorn: UInt32 = 0
    var skins: UInt32 = 0
    var seals: UInt32 = 0
    var regionsWoken: UInt32 = 0
    var relicsHeld: UInt32 = 0
    var cadreSize: UInt32 = 0
    var latticeRanks: UInt32 = 0
    var medalsWon: UInt32 = 0
    var medalTotal: UInt32 = 1
    var riteReady = false
    var untilDawn: UInt64 = 0
    var dawnStreak: UInt32 = 0
    var ascentTier: UInt32 = 0
    var ascentTotal: UInt32 = 1
    var badges: UInt32 = 0
    var greet: UInt16 = 0
    var questLive = false
    var questRegion: UInt32 = 0
    var questNode: UInt32 = 0
    var questDepth: UInt32 = 0
    var questChambers: UInt32 = 0

    init(_ scroll: inout Scroll) {
        purse = scroll.purse()
        attunement = scroll.quad()
        light = scroll.octet()
        lightFloor = scroll.octet()
        lightCeiling = scroll.octet()
        reawakenings = scroll.quad()
        dominion = scroll.ratio()
        switches = scroll.quad()
        tutorStep = scroll.quad()
        skinWorn = scroll.quad()
        skins = scroll.quad()
        seals = scroll.quad()
        regionsWoken = scroll.quad()
        relicsHeld = scroll.quad()
        cadreSize = scroll.quad()
        latticeRanks = scroll.quad()
        medalsWon = scroll.quad()
        medalTotal = scroll.quad()
        riteReady = scroll.flag()
        untilDawn = scroll.octet()
        dawnStreak = scroll.quad()
        ascentTier = scroll.quad()
        ascentTotal = scroll.quad()
        badges = scroll.quad()
        greet = scroll.pair()
        questLive = scroll.flag()
        questRegion = scroll.quad()
        questNode = scroll.quad()
        questDepth = scroll.quad()
        questChambers = scroll.quad()
    }

    var lightShare: Float {
        let span = lightCeiling > lightFloor ? Float(lightCeiling - lightFloor) : 1
        let done = light > lightFloor ? Float(light - lightFloor) : 0
        return min(1, max(0, done / span))
    }

    func on(_ flag: UInt32) -> Bool { switches & flag != 0 }
}

struct MapNodeView {
    var open = false
    var seals: UInt8 = 0
    var keystone = false
    var quota: UInt32 = 0
    var shardPay: UInt32 = 0
}

struct MapRegionView {
    var name: UInt16 = 0
    var blurb: UInt16 = 0
    var open = false
    var cleared: UInt32 = 0
    var nodeSpan: UInt32 = 0
    var hues: UInt32 = 0
    var features: UInt32 = 0
    var nodes: [MapNodeView] = []
}

struct MapView {
    var purse = Purse()
    var regions: [MapRegionView] = []
    var nodeTotal: UInt32 = 0
    var sealsWon: UInt32 = 0
    var sealCap: UInt32 = 1

    init(_ scroll: inout Scroll) {
        purse = scroll.purse()
        let span = scroll.tally()
        regions.reserveCapacity(span)
        for _ in 0..<span {
            var region = MapRegionView()
            region.name = scroll.pair()
            region.blurb = scroll.pair()
            region.open = scroll.flag()
            region.cleared = scroll.quad()
            region.nodeSpan = scroll.quad()
            region.hues = scroll.quad()
            region.features = scroll.quad()
            let nodeSpan = scroll.tally()
            region.nodes.reserveCapacity(nodeSpan)
            for _ in 0..<nodeSpan {
                var node = MapNodeView()
                node.open = scroll.flag()
                node.seals = scroll.byte()
                node.keystone = scroll.flag()
                node.quota = scroll.quad()
                node.shardPay = scroll.quad()
                region.nodes.append(node)
            }
            regions.append(region)
        }
        nodeTotal = scroll.quad()
        sealsWon = scroll.quad()
        sealCap = max(1, scroll.quad())
    }
}

struct LatticeNodeView {
    var name: UInt16 = 0
    var blurb: UInt16 = 0
    var branch: UInt32 = 0
    var rank: UInt32 = 0
    var ceiling: UInt32 = 1
    var shards: UInt64 = 0
    var cores: UInt64 = 0
    var attunement: UInt32 = 0
    var maxed = false
    var unlocked = false
    var affordable = false
}

struct LatticeView {
    var purse = Purse()
    var attunement: UInt32 = 0
    var branches: [(UInt16, UInt16)] = []
    var nodes: [LatticeNodeView] = []
    var ranks: UInt32 = 0
    var rankCap: UInt32 = 1

    init(_ scroll: inout Scroll) {
        purse = scroll.purse()
        attunement = scroll.quad()
        let branchSpan = scroll.tally()
        for _ in 0..<branchSpan { branches.append((scroll.pair(), scroll.pair())) }
        let nodeSpan = scroll.tally()
        for _ in 0..<nodeSpan {
            var node = LatticeNodeView()
            node.name = scroll.pair()
            node.blurb = scroll.pair()
            node.branch = scroll.quad()
            node.rank = scroll.quad()
            node.ceiling = max(1, scroll.quad())
            node.shards = scroll.octet()
            node.cores = scroll.octet()
            node.attunement = scroll.quad()
            node.maxed = scroll.flag()
            node.unlocked = scroll.flag()
            node.affordable = scroll.flag()
            nodes.append(node)
        }
        ranks = scroll.quad()
        rankCap = max(1, scroll.quad())
    }
}

struct ScarabView {
    var name: UInt16 = 0
    var blurb: UInt16 = 0
    var traitLine: UInt16 = 0
    var grade: UInt32 = 0
    var rank: UInt32 = 0
    var ceiling: UInt32 = 1
    var feed: UInt64 = 0
    var resin: UInt64 = 0
    var seat: Int32 = -1
    var awake = false
    var canRank = false
    var wakesAt: UInt32 = 0
}

struct PowerKindView {
    var name: UInt16 = 0
    var blurb: UInt16 = 0
    var rest: UInt32 = 0
    var unlocked = false
}

struct CadreView {
    var purse = Purse()
    var scarabs: [ScarabView] = []
    var bench: [Int32] = []
    var powerSeats: [Int32] = []
    var powers: [PowerKindView] = []

    init(_ scroll: inout Scroll) {
        purse = scroll.purse()
        let span = scroll.tally()
        for _ in 0..<span {
            var scarab = ScarabView()
            scarab.name = scroll.pair()
            scarab.blurb = scroll.pair()
            scarab.traitLine = scroll.pair()
            scarab.grade = scroll.quad()
            scarab.rank = scroll.quad()
            scarab.ceiling = max(1, scroll.quad())
            scarab.feed = scroll.octet()
            scarab.resin = scroll.octet()
            scarab.seat = scroll.signed()
            scarab.awake = scroll.flag()
            scarab.canRank = scroll.flag()
            scarab.wakesAt = scroll.quad()
            scarabs.append(scarab)
        }
        let benchSpan = scroll.tally()
        for _ in 0..<benchSpan { bench.append(scroll.signed()) }
        let seatSpan = scroll.tally()
        for _ in 0..<seatSpan { powerSeats.append(scroll.signed()) }
        let powerSpan = scroll.tally()
        for _ in 0..<powerSpan {
            var power = PowerKindView()
            power.name = scroll.pair()
            power.blurb = scroll.pair()
            power.rest = scroll.quad()
            power.unlocked = scroll.flag()
            powers.append(power)
        }
    }
}

struct RelicView {
    var name: UInt16 = 0
    var cluster: UInt32 = 0
    var home: UInt32 = 0
    var homeName: UInt16 = 0
    var held = false
}

struct RelicSetView {
    var name: UInt16 = 0
    var blurb: UInt16 = 0
    var held: UInt32 = 0
    var total: UInt32 = 1
    var complete = false
}

struct ReliquaryView {
    var purse = Purse()
    var relics: [RelicView] = []
    var clusters: [RelicSetView] = []

    init(_ scroll: inout Scroll) {
        purse = scroll.purse()
        let span = scroll.tally()
        for _ in 0..<span {
            var relic = RelicView()
            relic.name = scroll.pair()
            relic.cluster = scroll.quad()
            relic.home = scroll.quad()
            relic.homeName = scroll.pair()
            relic.held = scroll.flag()
            relics.append(relic)
        }
        let clusterSpan = scroll.tally()
        for _ in 0..<clusterSpan {
            var cluster = RelicSetView()
            cluster.name = scroll.pair()
            cluster.blurb = scroll.pair()
            cluster.held = scroll.quad()
            cluster.total = max(1, scroll.quad())
            cluster.complete = scroll.flag()
            clusters.append(cluster)
        }
    }
}

struct RecipeView {
    var name: UInt16 = 0
    var blurb: UInt16 = 0
    var resinToll: UInt32 = 0
    var shardToll: UInt32 = 0
    var made: UInt32 = 0
    var canMake = false
}

struct ForgeView {
    var purse = Purse()
    var recipes: [RecipeView] = []

    init(_ scroll: inout Scroll) {
        purse = scroll.purse()
        let span = scroll.tally()
        for _ in 0..<span {
            var recipe = RecipeView()
            recipe.name = scroll.pair()
            recipe.blurb = scroll.pair()
            recipe.resinToll = scroll.quad()
            recipe.shardToll = scroll.quad()
            recipe.made = scroll.quad()
            recipe.canMake = scroll.flag()
            recipes.append(recipe)
        }
    }
}

struct OfferView {
    var kind: UInt32 = 0
    var name: UInt16 = 0
    var blurb: UInt16 = 0
    var payPurse: UInt32 = 0
    var payAmount: UInt32 = 0
    var getPurse: UInt32 = 0
    var getAmount: UInt32 = 0
    var taken = false
    var affordable = false
}

struct CaravanView {
    var purse = Purse()
    var untilDawn: UInt64 = 0
    var offers: [OfferView] = []
    var skins: UInt32 = 0
    var skinWorn: UInt32 = 0

    init(_ scroll: inout Scroll) {
        purse = scroll.purse()
        untilDawn = scroll.octet()
        let span = scroll.tally()
        for _ in 0..<span {
            var offer = OfferView()
            offer.kind = scroll.quad()
            offer.name = scroll.pair()
            offer.blurb = scroll.pair()
            offer.payPurse = scroll.quad()
            offer.payAmount = scroll.quad()
            offer.getPurse = scroll.quad()
            offer.getAmount = scroll.quad()
            offer.taken = scroll.flag()
            offer.affordable = scroll.flag()
            offers.append(offer)
        }
        skins = scroll.quad()
        skinWorn = scroll.quad()
    }
}

struct RiteDayView {
    var shards: UInt32 = 0
    var cores: UInt32 = 0
    var resin: UInt32 = 0
    var extra: UInt32 = 0
    var today = false
}

struct RitesView {
    var purse = Purse()
    var slot: UInt32 = 0
    var streak: UInt32 = 0
    var ready = false
    var untilDawn: UInt64 = 0
    var claimsEver: UInt64 = 0
    var days: [RiteDayView] = []

    init(_ scroll: inout Scroll) {
        purse = scroll.purse()
        slot = scroll.quad()
        streak = scroll.quad()
        ready = scroll.flag()
        untilDawn = scroll.octet()
        claimsEver = scroll.octet()
        let span = scroll.tally()
        for _ in 0..<span {
            var day = RiteDayView()
            day.shards = scroll.quad()
            day.cores = scroll.quad()
            day.resin = scroll.quad()
            day.extra = scroll.quad()
            day.today = scroll.flag()
            days.append(day)
        }
    }
}

struct AscentStepView {
    var shards: UInt32 = 0
    var cores: UInt32 = 0
    var resin: UInt32 = 0
    var extra: UInt32 = 0
    var taken = false
    var claimable = false
}

struct AscentView {
    var purse = Purse()
    var tier: UInt32 = 0
    var tierCap: UInt32 = 1
    var light: UInt64 = 0
    var floor: UInt64 = 0
    var next: UInt64 = 1
    var steps: [AscentStepView] = []

    init(_ scroll: inout Scroll) {
        purse = scroll.purse()
        tier = scroll.quad()
        tierCap = max(1, scroll.quad())
        light = scroll.octet()
        floor = scroll.octet()
        next = max(1, scroll.octet())
        let span = scroll.tally()
        for _ in 0..<span {
            var step = AscentStepView()
            step.shards = scroll.quad()
            step.cores = scroll.quad()
            step.resin = scroll.quad()
            step.extra = scroll.quad()
            step.taken = scroll.flag()
            step.claimable = scroll.flag()
            steps.append(step)
        }
    }

    var share: Float {
        let span = next > floor ? Float(next - floor) : 1
        let done = light > floor ? Float(light - floor) : 0
        return min(1, max(0, done / span))
    }
}

struct EdictView {
    var line: UInt16 = 0
    var done: UInt64 = 0
    var need: UInt64 = 1
    var taken = false
    var ready = false
    var shards: UInt64 = 0
    var cores: UInt64 = 0
    var resin: UInt64 = 0

    var share: Float { min(1, Float(done) / Float(max(1, need))) }
}

struct ChronicleView {
    var line: UInt16 = 0
    var done: UInt64 = 0
    var need: UInt64 = 1
    var taken = false
    var ready = false
    var shardPrize: UInt32 = 0
    var corePrize: UInt32 = 0

    var share: Float { min(1, Float(done) / Float(max(1, need))) }
}

struct EdictsView {
    var purse = Purse()
    var rerolls: UInt32 = 0
    var dawn: [EdictView] = []
    var moon: [EdictView] = []
    var chronicles: [ChronicleView] = []
    var untilDawn: UInt64 = 0

    init(_ scroll: inout Scroll) {
        purse = scroll.purse()
        rerolls = scroll.quad()
        for block in 0..<2 {
            let span = scroll.tally()
            var batch: [EdictView] = []
            for _ in 0..<span {
                var edict = EdictView()
                edict.line = scroll.pair()
                edict.done = scroll.octet()
                edict.need = max(1, scroll.octet())
                edict.taken = scroll.flag()
                edict.ready = scroll.flag()
                edict.shards = scroll.octet()
                edict.cores = scroll.octet()
                edict.resin = scroll.octet()
                batch.append(edict)
            }
            if block == 0 { dawn = batch } else { moon = batch }
        }
        let chronicleSpan = scroll.tally()
        for _ in 0..<chronicleSpan {
            var chronicle = ChronicleView()
            chronicle.line = scroll.pair()
            chronicle.done = scroll.octet()
            chronicle.need = max(1, scroll.octet())
            chronicle.taken = scroll.flag()
            chronicle.ready = scroll.flag()
            chronicle.shardPrize = scroll.quad()
            chronicle.corePrize = scroll.quad()
            chronicles.append(chronicle)
        }
        untilDawn = scroll.octet()
    }
}

struct MedalView {
    var name: UInt16 = 0
    var blurb: UInt16 = 0
    var done: UInt64 = 0
    var need: UInt64 = 1
    var won = false
    var shardPrize: UInt32 = 0
    var corePrize: UInt32 = 0

    var share: Float { min(1, Float(done) / Float(max(1, need))) }
}

struct MedalsView {
    var purse = Purse()
    var medals: [MedalView] = []

    init(_ scroll: inout Scroll) {
        purse = scroll.purse()
        let span = scroll.tally()
        for _ in 0..<span {
            var medal = MedalView()
            medal.name = scroll.pair()
            medal.blurb = scroll.pair()
            medal.done = scroll.octet()
            medal.need = max(1, scroll.octet())
            medal.won = scroll.flag()
            medal.shardPrize = scroll.quad()
            medal.corePrize = scroll.quad()
            medals.append(medal)
        }
    }
}

struct CodexEntryView {
    var title: UInt16 = 0
    var body: UInt16 = 0
    var found = false
}

struct CodexView {
    var purse = Purse()
    var entries: [CodexEntryView] = []
    var tiles: [(UInt16, UInt16)] = []
    var breeds: [(UInt16, UInt16)] = []
    var goals: [(UInt16, UInt16)] = []

    init(_ scroll: inout Scroll) {
        purse = scroll.purse()
        let span = scroll.tally()
        for _ in 0..<span {
            var entry = CodexEntryView()
            entry.title = scroll.pair()
            entry.body = scroll.pair()
            entry.found = scroll.flag()
            entries.append(entry)
        }
        let tileSpan = scroll.tally()
        for _ in 0..<tileSpan { tiles.append((scroll.pair(), scroll.pair())) }
        let breedSpan = scroll.tally()
        for _ in 0..<breedSpan { breeds.append((scroll.pair(), scroll.pair())) }
        let goalSpan = scroll.tally()
        for _ in 0..<goalSpan { goals.append((scroll.pair(), scroll.pair())) }
    }
}

struct RecordsView {
    var purse = Purse()
    var lines: [(UInt16, UInt64)] = []
    var untouched: UInt64 = 0
    var keystoneClean: UInt64 = 0
    var shardsSpent: UInt64 = 0
    var seals: UInt32 = 0
    var sealCap: UInt32 = 1
    var relics: UInt32 = 0
    var relicCap: UInt32 = 1
    var medals: UInt32 = 0
    var medalCap: UInt32 = 1
    var latticeRanks: UInt32 = 0
    var latticeCap: UInt32 = 1
    var cadreRanks: UInt32 = 0
    var reawakenings: UInt32 = 0
    var wholeWorldWoken = false

    init(_ scroll: inout Scroll) {
        purse = scroll.purse()
        let span = scroll.tally()
        for _ in 0..<span { lines.append((scroll.pair(), scroll.octet())) }
        untouched = scroll.octet()
        keystoneClean = scroll.octet()
        shardsSpent = scroll.octet()
        seals = scroll.quad()
        sealCap = max(1, scroll.quad())
        relics = scroll.quad()
        relicCap = max(1, scroll.quad())
        medals = scroll.quad()
        medalCap = max(1, scroll.quad())
        latticeRanks = scroll.quad()
        latticeCap = max(1, scroll.quad())
        cadreRanks = scroll.quad()
        reawakenings = scroll.quad()
        wholeWorldWoken = scroll.flag()
    }
}
