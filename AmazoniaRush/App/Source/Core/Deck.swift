import AVFoundation
import UIKit

/// Audio deck. Short cues come from the bundled files; the ambient bed is
/// generated on the fly, so the app ships no music track at all and still has
/// a continuous score that never loops audibly.
final class Deck {
    static let shared = Deck()

    private var pools: [Int: [AVAudioPlayer]] = [:]
    private let engine = AVAudioEngine()
    private var drone: AVAudioSourceNode?
    private var bedRunning = false
    private var phases: [Double] = [0, 0, 0, 0, 0]
    private var drift: Double = 0
    private var noiseSeed: UInt32 = 0x5EED_1A7E
    private var bedLevel: Float = 0

    var cuesOn = true
    var bedOn = true

    private init() {}

    func prepare() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(interrupted(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    // --- short cues --------------------------------------------------------

    /// Warms the few cues used on the first two screens so the first tap is
    /// not the one that pays for disk access.
    func warm(_ cues: [Int]) {
        for cue in cues { _ = fetch(cue) }
    }

    func cue(_ index: Int, gain: Float = 1) {
        guard cuesOn, let bench = fetch(index) else { return }
        if let idle = bench.first(where: { !$0.isPlaying }) {
            idle.volume = gain
            idle.currentTime = 0
            idle.play()
        } else if let first = bench.first {
            first.volume = gain
            first.currentTime = 0
            first.play()
        }
    }

    private func fetch(_ index: Int) -> [AVAudioPlayer]? {
        if let known = pools[index] { return known }
        let leaf = Vault.cueLeaf(index)
        guard !leaf.isEmpty,
              let spot = Bundle.main.url(forResource: leaf, withExtension: Deck.cueKind)
        else { return nil }
        var bench: [AVAudioPlayer] = []
        for _ in 0..<2 {
            guard let voice = try? AVAudioPlayer(contentsOf: spot) else { break }
            voice.prepareToPlay()
            bench.append(voice)
        }
        guard !bench.isEmpty else { return nil }
        pools[index] = bench
        return bench
    }

    /// The file extension, assembled so it is not a literal in the binary.
    private static let cueKind = String(decoding: [0x6D, 0x70, 0x33])

    // --- generated bed -----------------------------------------------------

    func liftBed() {
        guard bedOn else { return }
        if !bedRunning { buildBed() }
        bedLevel = 0
        if !engine.isRunning { try? engine.start() }
    }

    func dropBed() {
        bedLevel = 0
        if engine.isRunning { engine.pause() }
    }

    private func buildBed() {
        let format = engine.outputNode.inputFormat(forBus: 0)
        let rate = format.sampleRate > 0 ? format.sampleRate : 44_100
        // Five partials tuned to a hollow fifth: a stone-room drone.
        let steps: [Double] = [55, 82.5, 110, 164.66, 220.5]

        let source = AVAudioSourceNode { [weak self] _, _, frames, slabs in
            guard let self else { return noErr }
            let lanes = UnsafeMutableAudioBufferListPointer(slabs)
            for frame in 0..<Int(frames) {
                self.drift += 1.0 / rate
                let sway = sin(self.drift * 0.07) * 0.5 + 0.5
                let bloom = sin(self.drift * 0.019 + 1.3) * 0.5 + 0.5
                let weights: [Double] = [
                    0.42,
                    0.14 + 0.1 * sway,
                    0.2,
                    0.07 + 0.06 * bloom,
                    0.05 * sway,
                ]
                var mix: Double = 0
                for (lane, step) in steps.enumerated() {
                    let weight = weights[lane]
                    self.phases[lane] += step * 2 * Double.pi / rate
                    if self.phases[lane] > 2 * Double.pi { self.phases[lane] -= 2 * Double.pi }
                    mix += sin(self.phases[lane]) * weight
                }
                // A whisper of sand on top.
                self.noiseSeed = self.noiseSeed &* 1_664_525 &+ 1_013_904_223
                let grain = Double(Int32(bitPattern: self.noiseSeed)) / Double(Int32.max)
                mix += grain * 0.016 * bloom

                if self.bedLevel < 0.5 { self.bedLevel += 0.000012 }
                let sample = Float(mix) * self.bedLevel * 0.5
                for lane in lanes {
                    guard let body = lane.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    body[frame] = sample
                }
            }
            return noErr
        }

        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: nil)
        engine.mainMixerNode.outputVolume = 0.7
        drone = source
        bedRunning = true
    }

    @objc private func interrupted(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let kind = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }
        if kind == .began {
            if engine.isRunning { engine.pause() }
        } else if bedOn {
            try? AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning { try? engine.start() }
        }
    }

    /// Read by the fight so the stick parks under whichever thumb the player
    /// said they use.
    private(set) var handedLeft = false
    /// Whether wounds are drawn. The fight is the same either way; only the
    /// blood on the floor changes.
    private(set) var goreOn = true

    func obey(_ switches: UInt32) {
        cuesOn = switches & Switch.sound != 0
        handedLeft = switches & Switch.leftHand != 0
        goreOn = switches & Switch.gore != 0
        let wanted = switches & Switch.music != 0
        if wanted != bedOn {
            bedOn = wanted
            if wanted { liftBed() } else { dropBed() }
        }
        Tremor.allowed = switches & Switch.haptics != 0
    }
}

/// Haptics, kept behind one gate so the settings switch really silences it.
enum Tremor {
    static var allowed = true
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let firm = UIImpactFeedbackGenerator(style: .medium)
    private static let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private static let judge = UINotificationFeedbackGenerator()

    static func tap() {
        guard allowed else { return }
        light.impactOccurred()
    }

    static func thud() {
        guard allowed else { return }
        firm.impactOccurred()
    }

    static func slam() {
        guard allowed else { return }
        heavy.impactOccurred()
    }

    static func cheer() {
        guard allowed else { return }
        judge.notificationOccurred(.success)
    }

    static func scold() {
        guard allowed else { return }
        judge.notificationOccurred(.error)
    }
}
