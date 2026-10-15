import UIKit

/// A switch row drawn by hand so the game keeps one visual language.
final class Lever: UIView {
    private let knob = UIView()
    private let track = Slab(.sunk, corner: 11)
    private var lit = false
    private var knobLeft: NSLayoutConstraint!
    var onFlip: ((Bool) -> Void)?

    init(_ title: String, _ note: String?) {
        super.init(frame: .zero)
        let heading = chisel(title, Scribe.carved(15), Hide.parchment, lines: 2)
        let column = UIStackView(arrangedSubviews: [heading])
        column.axis = .vertical
        column.spacing = 2
        if let note, !note.isEmpty {
            column.addArrangedSubview(chisel(note, Scribe.plain(11), Hide.murmur, lines: 0))
        }

        track.translatesAutoresizingMaskIntoConstraints = false
        knob.backgroundColor = Hide.parchment
        knob.layer.cornerRadius = 8
        knob.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(knob)

        let row = UIStackView(arrangedSubviews: [column, track])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        let card = Slab(.raised)
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)
        card.pin(into: self)

        knobLeft = knob.leadingAnchor.constraint(equalTo: track.leadingAnchor, constant: 3)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 11),
            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 13),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -13),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -11),
            track.widthAnchor.constraint(equalToConstant: 48),
            track.heightAnchor.constraint(equalToConstant: 22),
            knob.widthAnchor.constraint(equalToConstant: 16),
            knob.heightAnchor.constraint(equalToConstant: 16),
            knob.centerYAnchor.constraint(equalTo: track.centerYAnchor),
            knobLeft,
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(flip)))
    }

    required init?(coder: NSCoder) { nil }

    func set(_ on: Bool) {
        lit = on
        knobLeft.constant = on ? 29 : 3
        track.cast = on ? .lit : .sunk
        knob.backgroundColor = on ? Hide.gild : Hide.hush
    }

    @objc private func flip() {
        lit.toggle()
        UIView.animate(withDuration: 0.18) {
            self.set(self.lit)
            self.layoutIfNeeded()
        }
        Deck.shared.cue(lit ? Canvas.confirmCue : Canvas.toggleOffCue, gain: 0.6)
        Tremor.tap()
        onFlip?(lit)
    }
}

/// Settings, legal links, the offline notice and the prestige reset.
final class SettingsStage: ScrollStage {
    override var titleLexeme: UInt16? { Lexeme.setTitle }
    override var sceneWish: Int? { Canvas.aBgRoom2Scene }
    override var wantsPurse: Bool { false }

    override func awaken() {
        var scroll = Oracle.shared.ask(Rite.hub)
        paint(HubView(&scroll))
    }

    private func paint(_ hub: HubView) {
        clear()

        let flags: [(UInt16, UInt32)] = [
            (Lexeme.setSound, Switch.sound),
            (Lexeme.setMusic, Switch.music),
            (Lexeme.setHaptics, Switch.haptics),
            (Lexeme.setHints, Switch.hints),
            (Lexeme.setLefthand, Switch.leftHand),
            (Lexeme.setBold, Switch.bold),
            (Lexeme.setGore, Switch.gore),
        ]
        add(banner(Vault.say(Lexeme.setTitle)))
        for (lexeme, flag) in flags {
            let lever = Lever(Vault.say(lexeme), nil)
            lever.set(hub.on(flag))
            lever.onFlip = { [weak self] on in self?.toggle(flag, on) }
            add(lever)
        }

        add(banner(Vault.say(Lexeme.rateBanner), Hide.bruise))
        add(Ledge(
            title: Vault.say(Lexeme.rateTitle),
            blurb: Vault.say(Lexeme.rateBlurb),
            cast: .warn
        ))

        add(banner(Vault.say(Lexeme.uiOffline)))
        add(Ledge(
            title: Vault.say(Lexeme.netTitle),
            blurb: Vault.say(Lexeme.setOffline) + "\n" + Vault.say(Lexeme.netBlurb),
            cast: .lit
        ))

        add(banner(Vault.say(Lexeme.appTagline), Hide.hush))
        add(Ledge(
            title: Vault.say(Lexeme.uiPrivacy),
            blurb: Vault.say(Lexeme.setPrivacy),
            deed: Vault.say(Lexeme.navNext),
            fire: { [weak self] in self?.open(Lexeme.appPrivacy) }
        ))
        add(Ledge(
            title: Vault.say(Lexeme.uiSupport),
            blurb: Vault.say(Lexeme.setSupport),
            deed: Vault.say(Lexeme.navNext),
            fire: { [weak self] in self?.open(Lexeme.appSupport) }
        ))
        add(Ledge(
            title: Vault.say(Lexeme.setVersion),
            blurb: Vault.say(Lexeme.appBuild),
            cast: .sunk
        ))

        add(banner(Vault.say(Lexeme.uiDanger), Hide.bruise))
        add(Ledge(
            title: Vault.say(Lexeme.reawakenTitle),
            blurb: Vault.say(Lexeme.reawakenBlurb),
            tailTop: "x" + String(format: "%.2f", hub.dominion),
            cast: .warn,
            deed: Vault.say(Lexeme.navConfirm),
            deedBuild: .danger,
            deedLive: hub.regionsWoken >= 7,
            fire: { [weak self] in self?.askReawaken() }
        ))
        add(Ledge(
            title: Vault.say(Lexeme.setWipe),
            blurb: Vault.say(Lexeme.setWipeAsk),
            cast: .warn,
            deed: Vault.say(Lexeme.navConfirm),
            deedBuild: .danger,
            fire: { [weak self] in self?.askWipe() }
        ))
    }

    private func toggle(_ flag: UInt32, _ on: Bool) {
        var quill = Quill()
        quill.quad(flag)
        quill.flag(on)
        var scroll = Oracle.shared.ask(Rite.switchSet, quill.bytes)
        let hub = HubView(&scroll)
        Deck.shared.obey(hub.switches)
        Oracle.shared.preserve()
    }

    private func open(_ lexeme: UInt16) {
        guard let spot = URL(string: Vault.say(lexeme)), UIApplication.shared.canOpenURL(spot) else {
            whisper(Vault.say(Lexeme.webFailTitle), sour: true)
            return
        }
        UIApplication.shared.open(spot)
    }

    private func askReawaken() {
        ask(Vault.say(Lexeme.reawakenAsk)) { [weak self] in
            var scroll = Oracle.shared.ask(Rite.reawaken)
            let done = scroll.flag()
            let hub = HubView(&scroll)
            if done {
                Oracle.shared.preserve(force: true)
                Deck.shared.cue(Canvas.missionCompleteCue, gain: 0.9)
                Tremor.cheer()
            } else {
                self?.whisper(Vault.say(Lexeme.navLocked), sour: true)
            }
            self?.paint(hub)
        }
    }

    private func askWipe() {
        ask(Vault.say(Lexeme.setWipeAsk)) { [weak self] in
            Oracle.shared.wipeScroll()
            self?.whisper(Vault.say(Lexeme.uiWipeDone))
            self?.awaken()
        }
    }

    /// A hand-built confirmation sheet; no system alerts anywhere in the game.
    private func ask(_ question: String, _ deed: @escaping () -> Void) {
        let sheet = UIView()
        sheet.backgroundColor = Hide.pitch.withAlphaComponent(0.88)
        sheet.alpha = 0
        sheet.pin(into: view)

        let card = Slab(.warn)
        card.translatesAutoresizingMaskIntoConstraints = false
        sheet.addSubview(card)

        let line = chisel(question, Scribe.plain(14), Hide.parchment, lines: 0, align: .center)
        let yes = PressPad(.danger)
        yes.dress(Vault.say(Lexeme.navYes))
        let no = PressPad(.ghost)
        no.dress(Vault.say(Lexeme.navNo))
        let column = UIStackView(arrangedSubviews: [line, yes, no])
        column.axis = .vertical
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(column)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: sheet.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(equalTo: sheet.trailingAnchor, constant: -24),
            card.centerYAnchor.constraint(equalTo: sheet.centerYAnchor),
            column.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            column.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            column.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            column.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            yes.heightAnchor.constraint(equalToConstant: 46),
            no.heightAnchor.constraint(equalToConstant: 40),
        ])

        yes.onPress = {
            UIView.animate(withDuration: 0.18, animations: { sheet.alpha = 0 }) { _ in
                sheet.removeFromSuperview()
                deed()
            }
        }
        no.onPress = {
            UIView.animate(withDuration: 0.18, animations: { sheet.alpha = 0 }) { _ in
                sheet.removeFromSuperview()
            }
        }
        UIView.animate(withDuration: 0.22) { sheet.alpha = 1 }
        Deck.shared.cue(Canvas.popupOpenCue, gain: 0.7)
    }
}
