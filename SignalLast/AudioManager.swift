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
    private static var listenerPosition = CGPoint.zero
    private static var activeVoices: [AVAudioPlayerNode] = []
    private static var masterVolume: Float = 0.72

    static func setVolume(_ volume: Float) {
        masterVolume = min(max(volume, 0), 1)
        configureIfNeeded()
        engine.mainMixerNode.outputVolume = masterVolume
    }

    static func setListenerPosition(_ position: CGPoint) {
        listenerPosition = position
        configureIfNeeded()
        environment.listenerPosition = AVAudio3DPoint(
            x: Float(position.x / 100),
            y: Float(position.y / 100),
            z: 0
        )
    }

    /// Plays a spatialized cue at a scene-space position. A nil position means
    /// the listener location, preserving Phase 1's play(_:) call sites.
    static func play(_ cue: AudioCue, at position: CGPoint? = nil) {
        let resourceNames = resources(for: cue)
        guard let url = resourceNames.compactMap({ Bundle.main.url(forResource: $0, withExtension: "wav") }).first else { return }
        configureIfNeeded()

        do {
            let file = try AVAudioFile(forReading: url)
            let voice = AVAudioPlayerNode()
            engine.attach(voice)
            engine.connect(voice, to: environment, format: file.processingFormat)
            let source = position ?? listenerPosition
            voice.position = AVAudio3DPoint(
                x: Float(source.x / 100),
                y: Float(source.y / 100),
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
            // Optional or placeholder audio must never interrupt gameplay.
        }
    }

    private static func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true
        engine.attach(environment)
        engine.connect(environment, to: engine.mainMixerNode, format: nil)
        engine.mainMixerNode.outputVolume = masterVolume
        environment.listenerPosition = AVAudio3DPoint(
            x: Float(listenerPosition.x / 100),
            y: Float(listenerPosition.y / 100),
            z: 0
        )
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        } catch {
            // Keep the system audio session if the requested category is unavailable.
        }
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
