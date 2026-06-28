import AVFoundation

/// The handful of effects the game triggers.
enum Sound: CaseIterable {
    case fire        // shooter firing a bullet
    case explosion   // a centipede segment destroyed
    case mushroom    // a bullet chipping a mushroom
    case death       // the player losing a life
    case wave        // a wave cleared
}

/// Tiny procedural sound engine. Instead of shipping audio files (which a
/// SwiftPM executable can't easily bundle), we synthesize short square-wave
/// blips into PCM buffers at startup and play them through AVAudioEngine.
/// A small pool of player nodes lets effects overlap (e.g. rapid fire + a hit).
final class SoundEngine {
    static let shared = SoundEngine()

    private let engine = AVAudioEngine()
    private let format: AVAudioFormat
    private let sampleRate: Double = 44_100
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var enabled = false

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        // A pool of voices so overlapping sounds don't cut each other off.
        for _ in 0..<12 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }

        renderBuffers()

        do {
            try engine.start()
            players.forEach { $0.play() }
            enabled = true
        } catch {
            print("SoundEngine: audio engine failed to start — \(error)")
        }
    }

    func play(_ sound: Sound) {
        guard enabled, let buffer = buffers[sound] else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    // MARK: Synthesis

    private func renderBuffers() {
        // Quick high "pew" sweeping downward.
        buffers[.fire] = makeBuffer(duration: 0.10) { t in
            let freq = 1200.0 - 8000.0 * t
            let env = exp(-t * 28)
            return Float(self.square(max(freq, 200), t) * env * 0.26)
        }

        // Noise burst + descending tone for a segment popping.
        buffers[.explosion] = makeBuffer(duration: 0.38) { t in
            let env = exp(-t * 10)
            let noise = Double.random(in: -1...1)
            let tone = self.square(max(280.0 - 500.0 * t, 50), t)
            return Float((noise * 0.7 + tone * 0.3) * env * 0.42)
        }

        // Short low "tick" for chipping a mushroom.
        buffers[.mushroom] = makeBuffer(duration: 0.06) { t in
            let env = exp(-t * 55)
            return Float(self.square(190, t) * env * 0.20)
        }

        // Long descending wail for losing a life.
        buffers[.death] = makeBuffer(duration: 0.70) { t in
            let freq = 700.0 - 850.0 * t
            let vibrato = 1.0 + 0.04 * sin(2 * .pi * 14 * t)
            let env = t < 0.05 ? t / 0.05 : exp(-(t - 0.05) * 3)
            return Float(self.square(max(freq, 60) * vibrato, t) * env * 0.34)
        }

        // Rising arpeggio (C-E-G-C) when a wave is cleared.
        let notes: [Double] = [523.25, 659.25, 783.99, 1046.50]
        let noteDur = 0.09
        buffers[.wave] = makeBuffer(duration: noteDur * Double(notes.count)) { t in
            let idx = min(Int(t / noteDur), notes.count - 1)
            let local = t - Double(idx) * noteDur
            let env = exp(-local * 12)
            return Float(self.square(notes[idx], t) * env * 0.24)
        }
    }

    private func square(_ freq: Double, _ t: Double) -> Double {
        sin(2 * .pi * freq * t) >= 0 ? 1 : -1
    }

    private func makeBuffer(duration: Double, _ sample: (Double) -> Float) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let channel = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            channel[i] = max(-1, min(1, sample(t)))
        }
        return buffer
    }
}
