// A host-side harness. It links the same oracle archive the app links and
// drives every frame decoder, asserting each one consumes its frame exactly.
// Run through tools/run_probe.sh.

import Foundation

enum Vault {
    static func scrollLeaf() -> String { "probe.sealed" }
}

var faults = 0
var checks = 0

func expect(_ name: String, _ scroll: Scroll) {
    checks += 1
    if scroll.leftover != 0 {
        faults += 1
        print("  MISREAD \(name): \(scroll.leftover) bytes left over")
    }
}

func demand(_ name: String, _ truth: Bool) {
    checks += 1
    if !truth {
        faults += 1
        print("  WRONG \(name)")
    }
}

let hearth = Oracle.shared
hearth.awaken()

// Wind the clock the way the app does on every foreground.
var beat = hearth.heartbeat()
let opening = HubView(&beat)
expect("heartbeat", beat)
demand("purse ceiling", opening.purse.shardCeiling > 0)
demand("medal span", opening.medalTotal == 24)
demand("ascent span", opening.ascentTotal == 60)

var scroll = hearth.ask(Rite.hub)
let hub = HubView(&scroll)
expect("hub", scroll)

scroll = hearth.ask(Rite.map)
let atlas = MapView(&scroll)
expect("map", scroll)
demand("region count", atlas.regions.count == 7)
demand("node count", atlas.regions.allSatisfy { $0.nodes.count == 12 })
demand("first region open", atlas.regions.first?.open == true)

scroll = hearth.ask(Rite.lattice)
let lattice = LatticeView(&scroll)
expect("lattice", scroll)
demand("lattice nodes", lattice.nodes.count == 24)
demand("lattice branches", lattice.branches.count == 4)

scroll = hearth.ask(Rite.cadre)
let cadre = CadreView(&scroll)
expect("cadre", scroll)
demand("scarabs", cadre.scarabs.count == 8)
demand("powers", cadre.powers.count == 5)
demand("power seats", cadre.powerSeats.count >= 3)

scroll = hearth.ask(Rite.relics)
let relics = ReliquaryView(&scroll)
expect("relics", scroll)
demand("relic count", relics.relics.count == 16)
demand("relic sets", relics.clusters.count == 4)

scroll = hearth.ask(Rite.forge)
let forge = ForgeView(&scroll)
expect("forge", scroll)
demand("recipes", forge.recipes.count == 8)

scroll = hearth.ask(Rite.caravan)
let caravan = CaravanView(&scroll)
expect("caravan", scroll)
demand("offers", caravan.offers.count == 4)

scroll = hearth.ask(Rite.rites)
let rites = RitesView(&scroll)
expect("rites", scroll)
demand("rite cycle", rites.days.count == 7)
demand("rite ready on a fresh profile", rites.ready)

scroll = hearth.ask(Rite.ascent)
let ascent = AscentView(&scroll)
expect("ascent", scroll)
demand("ascent tiers", ascent.steps.count == 60)

scroll = hearth.ask(Rite.edicts)
let edicts = EdictsView(&scroll)
expect("edicts", scroll)
demand("dawn edicts", edicts.dawn.count == 3)
demand("moon edicts", edicts.moon.count == 3)
demand("chronicles", edicts.chronicles.count == 12)

scroll = hearth.ask(Rite.medals)
let medals = MedalsView(&scroll)
expect("medals", scroll)
demand("medal rows", medals.medals.count == 24)

scroll = hearth.ask(Rite.codex)
let codex = CodexView(&scroll)
expect("codex", scroll)
demand("codex entries", codex.entries.count == 14)
demand("stone guide", codex.stones.count == 14)
demand("hue guide", codex.hues.count == 4)

scroll = hearth.ask(Rite.records)
let records = RecordsView(&scroll)
expect("records", scroll)
demand("stat rows", records.lines.count == 16)

// --- text ------------------------------------------------------------------

scroll = hearth.ask(Rite.textSpan)
let lexemeSpan = scroll.count()
expect("textSpan", scroll)
demand("lexicon size", lexemeSpan == 557)

var blanks = 0
for lexeme in 0..<lexemeSpan {
    var line = hearth.ask(Rite.text, Quill.of(pair: UInt16(lexeme)))
    let body = line.run()
    if line.leftover != 0 { faults += 1; print("  MISREAD text \(lexeme)") }
    if body.isEmpty { blanks += 1 }
}
checks += 1
if blanks > 0 { faults += 1; print("  \(blanks) empty lexemes") }

// --- a full chamber --------------------------------------------------------

var request = Quill()
request.quad(0)
request.quad(0)
scroll = hearth.ask(Rite.trialOpen, request.bytes)
let allowed = scroll.flag()
var trial = TrialView(&scroll)
expect("trialOpen", scroll)
demand("first chamber opens", allowed)
demand("trial live", trial.live)
demand("board present", trial.chamber != nil)
demand("board size", trial.chamber?.cells.count == 60)
demand("quota set", (trial.chamber?.quota ?? 0) > 0)
demand("integrity set", (trial.chamber?.integrityFull ?? 0) > 0)

let founts = trial.chamber?.cells.filter { $0.stone == Stone.fount }.count ?? 0
let chalices = trial.chamber?.cells.filter { $0.stone == Stone.chalice }.count ?? 0
demand("has founts", founts > 0)
demand("has chalices", chalices > 0)

// Rotate every turnable stone once, the way a flailing player would.
var turnsAccepted = 0
for seat in 0..<60 {
    var reply = hearth.ask(Rite.trialTurn, Quill.of(pair: UInt16(seat)))
    if reply.flag() { turnsAccepted += 1 }
    let view = TrialView(&reply)
    if reply.leftover != 0 {
        faults += 1
        print("  MISREAD trialTurn seat \(seat)")
        break
    }
    trial = view
}
checks += 1
if turnsAccepted == 0 { faults += 1; print("  no stone accepted a turn") }

// Simulate four minutes of play at sixty frames a second.
var frames = 0
var omensSeen = 0
var stagesSeen = Set<UInt8>()
while frames < 14_400 {
    frames += 1
    var tick = Quill()
    tick.ratio(1.0 / 60.0)
    var reply = hearth.ask(Rite.trialTick, tick.bytes)
    let view = TrialView(&reply)
    if reply.leftover != 0 {
        faults += 1
        print("  MISREAD trialTick at frame \(frames): \(reply.leftover) left")
        break
    }
    trial = view
    omensSeen += view.chamber?.omens.count ?? 0
    stagesSeen.insert(view.stage)

    if view.stage == Phase.cleared {
        var onward = hearth.ask(Rite.trialPress)
        let next = TrialView(&onward)
        if onward.leftover != 0 { faults += 1; print("  MISREAD trialPress"); break }
        trial = next
    } else if view.stage == Phase.cache {
        var pick = Quill()
        pick.quad(0)
        var taken = hearth.ask(Rite.trialBoon, pick.bytes)
        let ok = taken.flag()
        let next = TrialView(&taken)
        if taken.leftover != 0 { faults += 1; print("  MISREAD trialBoon"); break }
        if !ok { faults += 1; print("  boon refused") }
        trial = next
    } else if view.stage == Phase.woken || view.stage == Phase.dark {
        break
    }
}
checks += 1
if omensSeen == 0 { faults += 1; print("  the board never reported an omen") }
checks += 1
if !stagesSeen.contains(Phase.weaving) { faults += 1; print("  never wove") }

print("  frames run \(frames), omens \(omensSeen), stages \(stagesSeen.sorted())")

// --- opening difficulty ----------------------------------------------------

// How the very first chamber treats a player who does nothing at all. If this
// resolves in seconds the opening is too sharp.
func measureIdleRoom() {
    var open = Quill()
    open.quad(0)
    open.quad(0)
    var reply = Oracle.shared.ask(Rite.trialOpen, open.bytes)
    _ = reply.flag()
    var view = TrialView(&reply)
    guard let room = view.chamber else { return }
    print("  room 1: quota \(room.quota), beats \(room.beatCap), integrity \(room.integrityFull), tempo \(room.tempo)")
    let turnable = room.cells.filter { !$0.isVoid && !$0.fixed }.count
    let kinds = Set(room.cells.filter { !$0.isVoid }.map(\.stone)).sorted()
    print("  room 1: \(turnable) turnable of \(room.cells.filter { !$0.isVoid }.count) live cells, stone kinds \(kinds)")

    var idleFrames = 0
    while idleFrames < 36_000 {
        idleFrames += 1
        var tick = Quill()
        tick.ratio(1.0 / 60.0)
        var step = Oracle.shared.ask(Rite.trialTick, tick.bytes)
        view = TrialView(&step)
        if view.stage != Phase.weaving { break }
    }
    let seconds = Double(idleFrames) / 60.0
    print("  room 1 idle: stage \(view.stage) after \(String(format: "%.1f", seconds))s"
        + ", integrity \(view.chamber?.integrity ?? 0)/\(view.chamber?.integrityFull ?? 0)"
        + ", delivered \(view.chamber?.delivered ?? 0)/\(view.chamber?.quota ?? 0)")
    _ = Oracle.shared.ask(Rite.trialAbandon)
}

measureIdleRoom()

// --- persistence -----------------------------------------------------------

hearth.preserve(force: true)
var blob = hearth.ask(Rite.saveBlob)
let sealed = blob.run()
expect("saveBlob", blob)
demand("save is sealed", sealed.count > 32)

print(faults == 0
    ? "probe clean: \(checks) checks"
    : "probe found \(faults) faults across \(checks) checks")
exit(faults == 0 ? 0 : 1)
