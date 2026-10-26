import AVFoundation

/// Replace the placeholder resource names below with the licensed audio files when ready.
enum AudioCue {
    case playerFootstep
    case glassBreak
    case deathAngelBreath
    case deathAngelScreech
    case demogorgonGrowl
}

enum AudioManager {
    private static var activePlayer: AVAudioPlayer?

    static func play(_ cue: AudioCue) {
        let resource: String
        switch cue {
        case .playerFootstep:
            resource = "player_step"
        case .glassBreak:
            // Phase 1 has no dedicated glass asset; use the footstep placeholder until one is supplied.
            resource = "player_step"
        case .deathAngelBreath, .deathAngelScreech:
            // Temporary bundled placeholder. Replace with deathAngelBreath.wav / deathAngelScreech.wav.
            resource = "creature_breath"
        case .demogorgonGrowl:
            // Hook reserved for Phase 2; no Demogorgon is instantiated in Phase 1.
            resource = "demogorgonGrowl"
        }

        guard let url = Bundle.main.url(forResource: resource, withExtension: "wav") else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            activePlayer = player
        } catch {
            // Missing or invalid optional sound resources should not interrupt gameplay.
        }
    }
}
