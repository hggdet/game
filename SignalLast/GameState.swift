import CoreGraphics

/// The player's current movement mode and its Arabic HUD label.
enum PlayerSpeed: String, Equatable {
    case idle
    case sneak
    case walk
    case run

    var arabicTitle: String {
        switch self {
        case .idle: return "ساكن"
        case .sneak: return "تسلّل"
        case .walk: return "مشي"
        case .run: return "ركض"
        }
    }
}

enum DeathAngelState: String, Equatable {
    case patrol
    case investigate
    case chase
    case search

    var arabicTitle: String {
        switch self {
        case .patrol: return "دورية"
        case .investigate: return "تحقيق"
        case .chase: return "اندفاع"
        case .search: return "بحث"
        }
    }
}

struct GameSnapshot: Equatable {
    var playerSpeed: PlayerSpeed = .idle
    var deathAngelState: DeathAngelState = .patrol
    var surface: NoiseSurface = .metal
    var noiseIntensity: CGFloat = 0
    var statusMessage = "حرّك العصا بلطف للتسلل بصمت."
}
