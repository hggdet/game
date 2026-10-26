import CoreHaptics
import UIKit

/// Produces a paired heartbeat whose interval tightens as an active monster
/// approaches. UIImpactFeedbackGenerator is used when Core Haptics is unavailable.
final class HeartbeatHaptics {
    private var engine: CHHapticEngine?
    private var timeUntilBeat: TimeInterval = 0
    private let fallback = UIImpactFeedbackGenerator(style: .heavy)
    var isEnabled = true

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let hapticEngine = try CHHapticEngine()
            hapticEngine.stoppedHandler = { [weak self] _ in
                do { try self?.engine?.start() } catch { }
            }
            hapticEngine.resetHandler = { [weak self] in
                do { try self?.engine?.start() } catch { }
            }
            try hapticEngine.start()
            engine = hapticEngine
        } catch {
            engine = nil
        }
    }

    func update(threat: CGFloat, delta: TimeInterval) {
        guard isEnabled else {
            timeUntilBeat = 0
            return
        }
        let clampedThreat = min(max(threat, 0), 1)
        guard clampedThreat > 0.08 else {
            timeUntilBeat = 0
            return
        }

        timeUntilBeat -= max(0, delta)
        guard timeUntilBeat <= 0 else { return }

        // Move from a cautious ~1.0 second beat to a fast ~0.30 second beat.
        let interval = 1.02 - Double(clampedThreat) * 0.72
        timeUntilBeat = max(0.28, interval)
        let intensity = Float(0.28 + clampedThreat * 0.68)
        if playCoreHapticsBeat(intensity: intensity) { return }

        fallback.prepare()
        fallback.impactOccurred(intensity: CGFloat(intensity))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.fallback.impactOccurred(intensity: CGFloat(min(1, intensity * 0.76)))
            self?.fallback.prepare()
        }
    }

    private func playCoreHapticsBeat(intensity: Float) -> Bool {
        guard let engine else { return false }
        let parameters = [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.22)
        ]
        let events = [
            CHHapticEvent(eventType: .hapticTransient, parameters: parameters, relativeTime: 0),
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.72),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.32)
                ],
                relativeTime: 0.13
            )
        ]
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            return false
        }
    }
}
