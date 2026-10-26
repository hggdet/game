import CoreHaptics
import UIKit

/// Produces a paired heartbeat whose interval tightens as an active monster
/// approaches. UIKit impact feedback is used when Core Haptics is unavailable.
final class HeartbeatHaptics {
    private var engine: CHHapticEngine?
    private var timeUntilBeat: TimeInterval = 0
    private var didLogCoreHapticsFailure = false
    private let fallback = UIImpactFeedbackGenerator(style: .heavy)
    var isEnabled = true

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let hapticEngine = try CHHapticEngine()
            engine = hapticEngine
            hapticEngine.stoppedHandler = { [weak self] _ in
                self?.restartEngineSafely()
            }
            hapticEngine.resetHandler = { [weak self] in
                self?.restartEngineSafely()
            }
            try hapticEngine.start()
        } catch {
            engine = nil
            logCoreHapticsFailure("تعذر بدء الاهتزازات اللمسية: \(error.localizedDescription)")
            // Haptics are optional and must never prevent the game from starting.
        }
    }

    func update(threat: CGFloat, delta: TimeInterval) {
        guard isEnabled else {
            timeUntilBeat = 0
            return
        }
        let safeThreat = threat.isFinite ? min(max(threat, 0), 1) : 0
        guard safeThreat > 0.08 else {
            timeUntilBeat = 0
            return
        }

        let safeDelta = delta.isFinite ? max(0, delta) : 0
        timeUntilBeat -= safeDelta
        guard timeUntilBeat <= 0 else { return }

        // Move from a cautious ~1.0 second beat to a fast ~0.30 second beat.
        let interval = 1.02 - Double(safeThreat) * 0.72
        timeUntilBeat = max(0.28, interval)
        let intensity = Float(0.28 + safeThreat * 0.68)
        if playCoreHapticsBeat(intensity: intensity) { return }

        fallback.prepare()
        fallback.impactOccurred(intensity: CGFloat(intensity))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, self.isEnabled else { return }
            self.fallback.impactOccurred(intensity: CGFloat(min(1, intensity * 0.76)))
            self.fallback.prepare()
        }
    }

    private func restartEngineSafely() {
        guard let engine else { return }
        do {
            try engine.start()
        } catch {
            self.engine = nil
            logCoreHapticsFailure("تعذر إعادة تشغيل محرك الاهتزاز: \(error.localizedDescription)")
        }
    }

    private func logCoreHapticsFailure(_ message: String) {
        guard !didLogCoreHapticsFailure else { return }
        didLogCoreHapticsFailure = true
        AppErrorLogger.append(AppErrorInfo(message: message, file: #fileID, line: #line))
    }

    private func playCoreHapticsBeat(intensity: Float) -> Bool {
        guard intensity.isFinite, let engine else { return false }
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
            logCoreHapticsFailure("تعذر إنشاء نبضة الاهتزاز: \(error.localizedDescription)")
            return false
        }
    }
}
