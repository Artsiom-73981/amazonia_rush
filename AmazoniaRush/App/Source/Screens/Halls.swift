import UIKit

/// The five halls the dock switches between. Each one is the root of its own
/// stack, so every screen opened from here gets a back arrow for free.
enum Halls {
    static func roots() -> [Stage] {
        [HomeStage(), HeroStage(), DailyStage(), AtlasStage(), MoreStage()]
    }
}

/// A plain menu row that opens another screen. Every door carries a carving:
/// a wall of identical text rows reads as a settings page, not as a temple.
private func door(
    _ title: UInt16,
    _ blurb: UInt16,
    art: Int? = nil,
    tail: String? = nil,
    _ open: @escaping () -> Void
) -> Ledge {
    Ledge(
        title: Vault.say(title),
        blurb: Vault.say(blurb),
        tailTop: tail,
        art: art.flatMap { Vault.prop($0) },
        cast: .raised,
        deed: Vault.say(Lexeme.navNext),
        deedBuild: .stone,
        deedWide: 86,
        fire: open
    )
}

/// A wide painted card: art on the left, a heading, a line of numbers and a
/// bar. Used at the top of a hall to give it a face.
private func plaque(
    art: Int,
    title: String,
    blurb: String,
    note: String? = nil,
    share: Float? = nil,
    beads: (Int, Int)? = nil
) -> UIView {
    let card = Slab(.raised)
    let badge = UIImageView(image: Vault.prop(art))
    badge.contentMode = .scaleAspectFit
    badge.translatesAutoresizingMaskIntoConstraints = false

    let heading = chisel(title, Scribe.carved(19, .bold), Hide.gild, lines: 2)
    let column = UIStackView(arrangedSubviews: [
        heading,
        chisel(blurb, Scribe.plain(11), Hide.murmur, lines: 0),
    ])
    column.axis = .vertical
    column.spacing = 4
    if let note {
        column.addArrangedSubview(chisel(note, Scribe.tally(12), Hide.parchment))
    }
    if let share {
        let bar = Meter(thickness: 7)
        bar.pour(share, animated: false)
        column.addArrangedSubview(bar)
    }
    if let (lit, total) = beads {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 5
        for slot in 0..<total {
            let bead = UIView()
            bead.backgroundColor = slot < lit ? Hide.gild : Hide.ink(48, 44, 36)
            bead.layer.cornerRadius = 5
            bead.measure(10, 10)
            row.addArrangedSubview(bead)
        }
        row.addArrangedSubview(UIView())
        column.addArrangedSubview(row)
    }

    let middle = UIStackView(arrangedSubviews: [badge, column])
    middle.axis = .horizontal
    middle.spacing = 12
    middle.alignment = .center
    middle.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(middle)
    NSLayoutConstraint.activate([
        badge.widthAnchor.constraint(equalToConstant: 78),
        badge.heightAnchor.constraint(equalToConstant: 92),
        middle.topAnchor.constraint(equalTo: card.topAnchor, constant: Grid.inset),
        middle.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Grid.inset),
        middle.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Grid.inset),
        middle.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Grid.inset),
    ])
    return card
}

/// The first hall's face: the Keeper herself, how far along she is, and the
/// line of flavour that used to float unattached above the cards.
private func crest(art: Int, level: String, greet: String, note: String, share: Float) -> UIView {
    let card = Slab(.raised)

    // A pool of light behind her, so she is standing in the temple rather
    // than pasted onto a panel.
    let pool = UIView()
    pool.backgroundColor = Hide.gild.withAlphaComponent(0.08)
    pool.layer.cornerRadius = 52
    pool.translatesAutoresizingMaskIntoConstraints = false

    let figure = UIImageView(image: Vault.prop(art))
    figure.contentMode = .scaleAspectFit
    figure.translatesAutoresizingMaskIntoConstraints = false

    let rank = chisel(level, Scribe.carved(26, .bold), Hide.gild)
    let line = chisel(greet, Scribe.plain(12), Hide.murmur, lines: 0)
    let bar = Meter(thickness: 7)
    bar.pour(share, animated: false)
    let column = UIStackView(arrangedSubviews: [
        rank,
        line,
        bar,
        chisel(note, Scribe.plain(10), Hide.hush, lines: 0),
    ])
    column.axis = .vertical
    column.spacing = 5
    column.translatesAutoresizingMaskIntoConstraints = false

    card.addSubview(pool)
    card.addSubview(figure)
    card.addSubview(column)
    NSLayoutConstraint.activate([
        pool.widthAnchor.constraint(equalToConstant: 104),
        pool.heightAnchor.constraint(equalToConstant: 104),
        pool.centerXAnchor.constraint(equalTo: figure.centerXAnchor),
        pool.centerYAnchor.constraint(equalTo: figure.centerYAnchor, constant: 6),

        figure.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Grid.inset),
        figure.centerYAnchor.constraint(equalTo: card.centerYAnchor),
        figure.widthAnchor.constraint(equalToConstant: 82),
        // Exactly, not at least: the artwork is 284 tall and would otherwise
        // stretch the card to its own idea of a good height.
        figure.heightAnchor.constraint(equalToConstant: 122),

        column.leadingAnchor.constraint(equalTo: figure.trailingAnchor, constant: 14),
        column.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Grid.inset),
        column.topAnchor.constraint(equalTo: card.topAnchor, constant: Grid.inset),
        column.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Grid.inset),
    ])
    return card
}

/// The one thing the hall is for. A door, a promise and a button as wide as
/// the card, because the way into a run should never look like a list row.
private func gate(
    art: Int,
    title: String,
    blurb: String,
    deed: String,
    build: PressPad.Build,
    fire: @escaping () -> Void
) -> UIView {
    let card = Slab(.lit)
    let badge = UIImageView(image: Vault.prop(art))
    badge.contentMode = .scaleAspectFit
    badge.translatesAutoresizingMaskIntoConstraints = false

    let words = UIStackView(arrangedSubviews: [
        chisel(title, Scribe.carved(18, .bold), Hide.gild, lines: 2),
        chisel(blurb, Scribe.plain(11), Hide.murmur, lines: 0),
    ])
    words.axis = .vertical
    words.spacing = 4

    let head = UIStackView(arrangedSubviews: [badge, words])
    head.axis = .horizontal
    head.spacing = 12
    head.alignment = .center

    let pad = PressPad(build)
    pad.dress(deed)
    pad.onPress = fire
    pad.translatesAutoresizingMaskIntoConstraints = false
    pad.heightAnchor.constraint(equalToConstant: 46).isActive = true

    let column = UIStackView(arrangedSubviews: [head, pad])
    column.axis = .vertical
    column.spacing = 12
    column.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(column)
    NSLayoutConstraint.activate([
        badge.widthAnchor.constraint(equalToConstant: 58),
        badge.heightAnchor.constraint(equalToConstant: 70),
        column.topAnchor.constraint(equalTo: card.topAnchor, constant: Grid.inset),
        column.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Grid.inset),
        column.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -Grid.inset),
        column.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Grid.inset),
    ])
    return card
}

/// One number worth looking at: a carving, the figure, and what it counts.
private func tile(art: Int, value: String, name: String) -> UIView {
    let card = Slab(.sunk)
    let badge = UIImageView(image: Vault.prop(art))
    badge.contentMode = .scaleAspectFit
    badge.translatesAutoresizingMaskIntoConstraints = false

    let figure = chisel(value, Scribe.tally(19), Hide.gild)
    let caption = chisel(name, Scribe.plain(10), Hide.murmur, lines: 2)
    let words = UIStackView(arrangedSubviews: [figure, caption])
    words.axis = .vertical
    words.spacing = 1

    let middle = UIStackView(arrangedSubviews: [badge, words])
    middle.axis = .horizontal
    middle.spacing = 9
    middle.alignment = .center
    middle.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(middle)
    NSLayoutConstraint.activate([
        badge.widthAnchor.constraint(equalToConstant: 38),
        badge.heightAnchor.constraint(equalToConstant: 38),
        middle.topAnchor.constraint(equalTo: card.topAnchor, constant: 9),
        middle.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
        middle.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
        middle.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -9),
    ])
    return card
}

/// Lays tiles two to a row. Four short cards read in one glance; four rows of
/// mostly empty panel read as a form to fill in.
private func pairs(_ cards: [UIView]) -> UIView {
    let column = UIStackView()
    column.axis = .vertical
    column.spacing = Grid.tight
    for seat in stride(from: 0, to: cards.count, by: 2) {
        let row = UIStackView(arrangedSubviews: Array(cards[seat..<min(seat + 2, cards.count)]))
        row.axis = .horizontal
        row.spacing = Grid.tight
        row.distribution = .fillEqually
        column.addArrangedSubview(row)
    }
    return column
}

// --- the descent -----------------------------------------------------------

/// Hall one: where you are in the temple and the way back into a run.
final class HomeStage: ScrollStage {
    override var titleLexeme: UInt16? { Lexeme.homeTitle }
    override var sceneWish: Int? { Canvas.aUniversalBgEntranceScene }

    override func awaken() {
        var scroll = Oracle.shared.heartbeat()
        let sheet = HubView(&scroll)
        hoard.show(sheet.purse)
        Director.shared.markDaily(sheet.riteReady)
        rebuild(sheet)
    }

    private func rebuild(_ sheet: HubView) {
        clear()

        add(crest(
            art: Canvas.bKeeper[0],
            level: Vault.say(Lexeme.homeLevel) + "  \(sheet.attunement)",
            greet: Vault.say(sheet.greet),
            note: Vault.say(Lexeme.homeLevelBlurb),
            share: sheet.lightShare
        ))

        // A run already underway outranks everything: it is the only card
        // with the gold button until it is finished or abandoned.
        if sheet.questLive {
            add(gate(
                art: Canvas.bTempleDoors[0],
                title: Vault.say(Lexeme.homeResume),
                blurb: Vault.say(Lexeme.homeResumeBlurb)
                    .replacingOccurrences(of: "%1", with: "\(sheet.questDepth)"),
                deed: Vault.say(Lexeme.navResume),
                build: .gold,
                fire: { Director.shared.go(DelveStage()) }
            ))
            add(Ledge(
                title: Vault.say(Lexeme.mapTitle),
                blurb: Vault.say(Lexeme.mapHint),
                art: Vault.prop(Canvas.bAncientSymbols[0]),
                cast: .raised,
                deed: Vault.say(Lexeme.navNext),
                deedBuild: .stone,
                deedWide: 86,
                fire: { Director.shared.go(MapStage()) }
            ))
        } else {
            add(gate(
                art: Canvas.bTempleDoors[0],
                title: Vault.say(Lexeme.mapTitle),
                blurb: Vault.say(Lexeme.mapHint),
                deed: Vault.say(Lexeme.homeBegin),
                build: .gold,
                fire: { Director.shared.go(MapStage()) }
            ))
        }

        // The day's claim is worth a card of its own while it is unclaimed,
        // and worth nothing at all once it is taken.
        if sheet.riteReady {
            add(Ledge(
                title: Vault.say(Lexeme.riteTitle),
                blurb: Vault.say(Lexeme.riteBlurb),
                art: Vault.prop(Canvas.aTreasureChests[0]),
                cast: .lit,
                deed: Vault.say(Lexeme.navNext),
                deedBuild: .gold,
                deedWide: 86,
                fire: { Director.shared.swap(to: 2) }
            ))
        }

        add(banner(Vault.say(Lexeme.uiProgress)))
        add(pairs([
            tile(
                art: Canvas.bAncientSymbols[1],
                value: "\(sheet.seals)",
                name: Vault.say(Lexeme.mapStars)
            ),
            tile(
                art: Canvas.aAncientRelics[1],
                value: "\(sheet.relicsHeld)",
                name: Vault.say(Lexeme.relicTitle)
            ),
            tile(
                art: Canvas.bAncientSymbols[0],
                value: "\(sheet.medalsWon) / \(sheet.medalTotal)",
                name: Vault.say(Lexeme.medalsTitle)
            ),
            tile(
                art: Canvas.aMagicCrystals[0],
                value: "\(sheet.latticeRanks)",
                name: Vault.say(Lexeme.latticeTitle)
            ),
            tile(
                art: Canvas.aLargePyramids[0],
                value: "\(sheet.regionsWoken)",
                name: Vault.say(Lexeme.homeRegions)
            ),
            tile(
                art: Canvas.bSolarDevices[1],
                value: "\(sheet.ascentTier) / \(sheet.ascentTotal)",
                name: Vault.say(Lexeme.ascentTitle)
            ),
        ]))
    }
}

// --- the hero --------------------------------------------------------------

/// Hall two: everything you spend loot on.
final class HeroStage: ScrollStage {
    override var titleLexeme: UInt16? { Lexeme.heroTitle }
    override var sceneWish: Int? { Canvas.bBgUndergroundTempleScene }

    override func awaken() {
        var scroll = Oracle.shared.ask(Rite.hub)
        let sheet = HubView(&scroll)
        hoard.show(sheet.purse)
        clear()
        add(plaque(
            art: Canvas.bScarabBasic[1],
            title: Vault.say(Lexeme.homeLevel) + "  \(sheet.attunement)",
            blurb: Vault.say(Lexeme.tabHeroBlurb),
            note: Vault.say(Lexeme.latticeTitle) + "  \(sheet.latticeRanks)   "
                + Vault.say(Lexeme.relicTitle) + "  \(sheet.relicsHeld)",
            share: sheet.lightShare
        ))
        add(banner(Vault.say(Lexeme.uiProgress)))
        add(door(
            Lexeme.heroTabSkills, Lexeme.latticeBlurb,
            art: Canvas.aMagicCrystals[0], tail: "\(sheet.latticeRanks)"
        ) { Director.shared.go(LatticeStage()) })
        add(door(
            Lexeme.heroTabScarabs, Lexeme.cadreBlurb,
            art: Canvas.bScarabSupport[1], tail: "\(sheet.cadreSize)"
        ) { Director.shared.go(CadreStage()) })
        add(door(
            Lexeme.heroTabRelics, Lexeme.relicBlurb,
            art: Canvas.aAncientRelics[1], tail: "\(sheet.relicsHeld)"
        ) { Director.shared.go(ReliquaryStage()) })
        add(door(
            Lexeme.heroTabWorkshop, Lexeme.forgeBlurb,
            art: Canvas.bTempleMechanisms[0]
        ) { Director.shared.go(ForgeStage()) })
        add(door(
            Lexeme.heroTabCaravan, Lexeme.caravanBlurb,
            art: Canvas.aCeremonialVessels[1]
        ) { Director.shared.go(CaravanStage()) })
    }
}

// --- the day ---------------------------------------------------------------

/// Hall three: the things that reset on their own.
final class DailyStage: ScrollStage {
    override var titleLexeme: UInt16? { Lexeme.dailyTitle }
    override var sceneWish: Int? { Canvas.aBgRoom3Scene }

    override func awaken() {
        var scroll = Oracle.shared.ask(Rite.hub)
        let sheet = HubView(&scroll)
        hoard.show(sheet.purse)
        clear()
        Director.shared.markDaily(sheet.riteReady)
        add(plaque(
            art: Canvas.bEnvironmentProps[1],
            title: Vault.say(Lexeme.dailyTitle),
            blurb: Vault.say(Lexeme.riteBlurb),
            note: Vault.say(Lexeme.riteStreak)
                .replacingOccurrences(of: "%1", with: "\(sheet.dawnStreak)"),
            beads: (Int(min(7, sheet.dawnStreak)), 7)
        ))
        if sheet.riteReady {
            add(banner(Vault.say(Lexeme.homeReadyBadge), Hide.ember))
        }
        add(Ledge(
            title: Vault.say(Lexeme.dailyTabRites),
            blurb: Vault.say(Lexeme.riteBlurb),
            tailTop: sheet.riteReady ? nil : Digits.clockFace(sheet.untilDawn),
            art: Vault.prop(Canvas.aTreasureChests[1]),
            cast: sheet.riteReady ? .lit : .raised,
            deed: Vault.say(sheet.riteReady ? Lexeme.navClaim : Lexeme.navNext),
            deedBuild: sheet.riteReady ? .gold : .stone,
            fire: { Director.shared.go(RitesStage()) }
        ))
        add(door(
            Lexeme.dailyTabGoals, Lexeme.edictsBlurb,
            art: Canvas.bAncientSymbols[0]
        ) { Director.shared.go(EdictsStage()) })
        add(Ledge(
            title: Vault.say(Lexeme.dailyTabAscent),
            blurb: Vault.say(Lexeme.ascentBlurb),
            tailTop: "\(sheet.ascentTier) / \(sheet.ascentTotal)",
            share: Float(sheet.ascentTier) / Float(max(1, sheet.ascentTotal)),
            art: Vault.prop(Canvas.aObelisks[0]),
            cast: .raised,
            deed: Vault.say(Lexeme.navNext),
            fire: { Director.shared.go(AscentStage()) }
        ))
        add(chisel(Vault.say(Lexeme.riteOffline), Scribe.plain(11), Hide.hush, lines: 0))
    }
}

// --- the atlas -------------------------------------------------------------

/// Hall four: everything the game knows and is willing to explain.
final class AtlasStage: ScrollStage {
    override var titleLexeme: UInt16? { Lexeme.atlasTitle }
    override var sceneWish: Int? { Canvas.bBgObservatoryControlHallScene }

    override func awaken() {
        var scroll = Oracle.shared.ask(Rite.hub)
        let sheet = HubView(&scroll)
        hoard.show(sheet.purse)
        clear()
        add(plaque(
            art: Canvas.bAncientSymbols[3],
            title: Vault.say(Lexeme.atlasTitle),
            blurb: Vault.say(Lexeme.tabAtlasBlurb),
            note: Vault.say(Lexeme.medalsTitle)
                + "  \(sheet.medalsWon)/\(sheet.medalTotal)",
            share: Float(sheet.medalsWon) / Float(max(1, sheet.medalTotal))
        ))
        add(door(
            Lexeme.atlasTabCodex, Lexeme.atlasLoreBlurb,
            art: Canvas.bAncientSymbols[1]
        ) { Director.shared.go(CodexStage(.lore)) })
        add(door(
            Lexeme.atlasTabBestiary, Lexeme.atlasBreedsBlurb,
            art: Canvas.aGodStatues[0], tail: "\(Breed.kinds)"
        ) { Director.shared.go(CodexStage(.breeds)) })
        add(door(
            Lexeme.atlasTabTiles, Lexeme.atlasTilesBlurb,
            art: Canvas.aAncientRelics[0]
        ) { Director.shared.go(CodexStage(.tiles)) })
        add(door(
            Lexeme.atlasTabGoals, Lexeme.atlasGoalsBlurb,
            art: Canvas.bTempleDoors[0]
        ) { Director.shared.go(CodexStage(.goals)) })
        add(door(
            Lexeme.atlasTabMedals, Lexeme.atlasMedalsBlurb,
            art: Canvas.aAncientRelics[3], tail: "\(sheet.medalsWon)"
        ) { Director.shared.go(MedalsStage()) })
        add(door(
            Lexeme.atlasTabRecords, Lexeme.atlasRecordsBlurb,
            art: Canvas.bTempleMechanisms[1]
        ) { Director.shared.go(RecordsStage()) })
    }
}

// --- the rest --------------------------------------------------------------

/// Hall five: settings, the legal pages and the offline promise.
final class MoreStage: ScrollStage {
    override var titleLexeme: UInt16? { Lexeme.tabMore }
    override var sceneWish: Int? { Canvas.aBgRoom2Scene }

    override func awaken() {
        var scroll = Oracle.shared.ask(Rite.hub)
        let sheet = HubView(&scroll)
        hoard.show(sheet.purse)
        clear()
        add(door(
            Lexeme.setTitle, Lexeme.tabMoreBlurb,
            art: Canvas.bTempleMechanisms[0]
        ) { Director.shared.go(SettingsStage()) })
        add(banner(Vault.say(Lexeme.setLegal)))
        add(Ledge(
            title: Vault.say(Lexeme.uiPrivacy),
            blurb: Vault.say(Lexeme.setPrivacy),
            cast: .sunk,
            deed: Vault.say(Lexeme.navNext),
            deedWide: 86,
            fire: { Director.shared.go(WebStage(Lexeme.uiPrivacy, Lexeme.appPrivacy)) }
        ))
        add(Ledge(
            title: Vault.say(Lexeme.uiSupport),
            blurb: Vault.say(Lexeme.setSupport),
            cast: .sunk,
            deed: Vault.say(Lexeme.navNext),
            deedWide: 86,
            fire: { Director.shared.go(WebStage(Lexeme.uiSupport, Lexeme.appSupport)) }
        ))
        add(banner(Vault.say(Lexeme.uiOffline), Hide.verdure))
        add(chisel(Vault.say(Lexeme.netBlurb), Scribe.plain(12), Hide.murmur, lines: 0))
        add(chisel(
            Vault.say(Lexeme.setVersion) + "  " + Vault.say(Lexeme.appBuild),
            Scribe.plain(11), Hide.hush
        ))
    }
}

#if DEBUG
/// Drives the app from launch arguments so screens can be inspected on a
/// headless simulator. Debug builds only; the shipped game has no such door.
enum Tour {
    /// `--hall 2` opens the third tab straight away.
    static var hall: Int? {
        guard let seat = value(for: "--hall"), let index = Int(seat) else { return nil }
        return max(0, min(4, index))
    }

    /// `--open map` or `--open run` pushes one more screen on top.
    static func walk() {
        guard let leaf = value(for: "--open") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            switch leaf {
            case "map": Director.shared.go(MapStage())
            case "walk":
                let sands = MapStage()
                Director.shared.go(sands)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { sands.rehearse(2) }
            case "run":
                var quill = Quill()
                quill.quad(0)
                quill.quad(0)
                _ = Oracle.shared.descend(Rite.delveOpen, quill.bytes)
                // `--idle 2` runs a couple of seconds of the fight with
                // nobody at the stick, which is how a chamber can be looked at
                // without a finger on glass.
                if let count = value(for: "--idle"), let spans = Int(count) {
                    for _ in 0..<max(0, spans * 20) {
                        var pass = Quill()
                        pass.signed(0)
                        pass.signed(0)
                        pass.quad(50)
                        _ = Oracle.shared.descend(Rite.delveAct, pass.bytes)
                    }
                }
                let run = DelveStage()
                Director.shared.go(run)
                if value(for: "--drive") != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { run.rehearse() }
                }
            case "saga":
                Saga.shared.open(chapter: 2) {}
            case "skills": Director.shared.go(LatticeStage())
            case "scarabs": Director.shared.go(CadreStage())
            case "rites": Director.shared.go(RitesStage())
            case "bestiary": Director.shared.go(CodexStage(.breeds))
            case "settings": Director.shared.go(SettingsStage())
            case "privacy": Director.shared.go(WebStage(Lexeme.uiPrivacy, Lexeme.appPrivacy))
            default: break
            }
        }
    }

    private static func value(for flag: String) -> String? {
        let parts = CommandLine.arguments
        guard let seat = parts.firstIndex(of: flag), seat + 1 < parts.count else { return nil }
        return parts[seat + 1]
    }
}
#endif
