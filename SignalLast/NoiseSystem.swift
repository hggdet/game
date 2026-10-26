import CoreGraphics
import Foundation

enum NoiseSurface: String, Equatable {
    case metal
    case carpet
    case glass

    var radiusMultiplier: CGFloat {
        switch self {
        case .metal: return 1.35
        case .carpet: return 0.55
        case .glass: return 1.85
        }
    }

    var arabicTitle: String {
        switch self {
        case .metal: return "معدن"
        case .carpet: return "سجاد"
        case .glass: return "زجاج"
        }
    }
}

enum NoiseSource: String, Equatable {
    case footstep
    case runningFootstep
    case glassBreak
    case thrownItem
    case loudPickup
}

struct NoiseEvent: Equatable, Identifiable {
    let id: UUID
    let position: CGPoint
    let radius: CGFloat
    let source: NoiseSource
    let surface: NoiseSurface
    let timestamp: TimeInterval

    init(position: CGPoint, radius: CGFloat, source: NoiseSource, surface: NoiseSurface, timestamp: TimeInterval) {
        self.id = UUID()
        self.position = position
        self.radius = max(0, radius)
        self.source = source
        self.surface = surface
        self.timestamp = timestamp
    }
}

/// A small event bus. Hunters receive a noise's origin and radius, never the player's live position.
final class NoiseSystem {
    var onNoise: ((NoiseEvent) -> Void)?
    private(set) var latestEvent: NoiseEvent?

    func emit(source: NoiseSource, at position: CGPoint, baseRadius: CGFloat, surface: NoiseSurface, time: TimeInterval) {
        let event = NoiseEvent(
            position: position,
            radius: baseRadius * surface.radiusMultiplier,
            source: source,
            surface: surface,
            timestamp: time
        )
        latestEvent = event
        onNoise?(event)
    }
}
