import AVFoundation
import CoreGraphics

enum AudioCue {
    case playerFootstep
    case glassBreak
    case deathAngelBreath
    case deathAngelScreech
    case demogorgonGrowl
    case distantFootsteps
    case distantStationAmbience
    case doorRattle
    case flareIgnition
    case transmissionStart
    case transmissionComplete
}

enum AudioManager {
    private static let engine = AVAudioEngine()
    private static let environment = AVAudioEnvironmentNode()
    private static var isConfigured = false
    private static var audioUnavailable = false
    private static var loggedAudioFailures = Set<String>()
    private static var listenerPosition = CGPoint.zero
    private static var activeVoices: [AVAudioPlayerNode] = []
    private static var masterVolume: Float = 0.72

    static func setVolume(_ volume: Float) {
        masterVolume = volume.isFinite ? min(max(volume, 0), 1) : 0.72
        guard configureIfNeeded() else { return }
        engine.mainMixerNode.outputVolume = masterVolume
    }

    static func setListenerPosition(_ position: CGPoint) {
        guard position.x.isFinite, position.y.isFinite else { return }
        listenerPosition = position
        guard configureIfNeeded() else { return }
        environment.listenerPosition = AVAudio3DPoint(
            x: Float(position.x / 100),
            y: Float(position.y / 100),
            z: 0
        )
    }

    /// Plays a spatialized cue at a scene-space position. Missing or invalid
    /// optional audio is intentionally silent and never blocks gameplay.
    static func play(_ cue: AudioCue, at position: CGPoint? = nil) {
        guard !audioUnavailable else { return }
        let candidateURLs = resources(for: cue).compactMap { Bundle.main.url(forResource: $0, withExtension: "wav") }
        guard !candidateURLs.isEmpty else { return }
        guard configureIfNeeded() else { return }

        var playableFile: AVAudioFile?
        for url in candidateURLs {
            do {
                let candidate = try AVAudioFile(forReading: url)
                let format = candidate.processingFormat
                guard format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0 else {
                    logAudioFailure("تنسيق الملف الصوتي غير صالح: \(url.lastPathComponent)", key: "format:\(url.lastPathComponent)")
                    continue
                }
                playableFile = candidate
                break
            } catch {
                logAudioFailure("تعذر قراءة الملف الصوتي \(url.lastPathComponent): \(error.localizedDescription)", key: "read:\(url.lastPathComponent)")
            }
        }
        guard let file = playableFile else { return }

        let voice = AVAudioPlayerNode()
        var didAttachVoice = false
        do {
            let format = file.processingFormat
            engine.attach(voice)
            didAttachVoice = true
            // Match the source node to the file's processing format exactly.
            // Each playback gets a fresh node and is connected only once.
            engine.connect(voice, to: environment, format: format)
            let source = position ?? listenerPosition
            let safeX = source.x.isFinite ? source.x : listenerPosition.x
            let safeY = source.y.isFinite ? source.y : listenerPosition.y
            voice.position = AVAudio3DPoint(
                x: Float(safeX / 100),
                y: Float(safeY / 100),
                z: -1
            )
            if !engine.isRunning {
                try engine.start()
            }
            activeVoices.append(voice)
            voice.scheduleFile(file, at: nil) {
                DispatchQueue.main.async {
                    voice.stop()
                    engine.disconnectNodeOutput(voice)
                    engine.detach(voice)
                    activeVoices.removeAll { $0 === voice }
                }
            }
            voice.play()
        } catch {
            if didAttachVoice {
                voice.stop()
                engine.disconnectNodeOutput(voice)
                engine.detach(voice)
            }
            audioUnavailable = true
            logAudioFailure("تعذر تشغيل محرك الصوت: \(error.localizedDescription)", key: "engine-start")
            // Audio is optional: retain a silent but playable game session.
        }
    }

    private static func configureIfNeeded() -> Bool {
        guard !audioUnavailable else { return false }
        guard !isConfigured else { return true }

        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        } catch {
            // Continue with the system's current session configuration.
            logAudioFailure("تعذر ضبط جلسة الصوت: \(error.localizedDescription)", key: "session-category")
        }

        engine.attach(environment)
        engine.connect(environment, to: engine.mainMixerNode, format: nil)
        engine.mainMixerNode.outputVolume = masterVolume
        environment.listenerPosition = AVAudio3DPoint(
            x: Float(listenerPosition.x / 100),
            y: Float(listenerPosition.y / 100),
            z: 0
        )
        isConfigured = true
        return true
    }

    private static func logAudioFailure(_ message: String, key: String) {
        guard loggedAudioFailures.insert(key).inserted else { return }
        AppErrorLogger.append(AppErrorInfo(message: message, file: #fileID, line: #line))
    }

    private static func resources(for cue: AudioCue) -> [String] {
        switch cue {
        case .playerFootstep:
            return ["player_step"]
        case .glassBreak:
            return ["glass_break", "player_step"]
        case .deathAngelBreath:
            return ["deathAngelBreath", "creature_breath"]
        case .deathAngelScreech:
            return ["deathAngelScreech", "creature_breath"]
        case .demogorgonGrowl:
            return ["demogorgonGrowl", "creature_breath"]
        case .distantFootsteps:
            return ["distant_footsteps", "player_step"]
        case .distantStationAmbience:
            return ["station_ambience", "distant_footsteps", "player_step"]
        case .doorRattle:
            return ["door_rattle", "player_step"]
        case .flareIgnition:
            return ["flare_ignition", "player_step"]
        case .transmissionStart:
            return ["transmission_start", "door_rattle", "player_step"]
        case .transmissionComplete:
            return ["transmission_complete", "creature_breath", "player_step"]
        }
    }
}
