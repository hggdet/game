import SpriteKit
import UIKit

enum FlashlightLevel: String, CaseIterable, Equatable, Codable {
    case flash
    case steady
    case strong

    var arabicTitle: String {
        switch self {
        case .flash: return "وميض"
        case .steady: return "ثابت"
        case .strong: return "قوي"
        }
    }

    /// How far the beam reveals tiles, in scene points before scene scaling.
    var revealRange: CGFloat {
        switch self {
        case .flash: return 112
        case .steady: return 184
        case .strong: return 258
        }
    }

    /// Demogorgon can only spot the player inside this light-dependent radius.
    var detectionRange: CGFloat {
        switch self {
        case .flash: return 92
        case .steady: return 158
        case .strong: return 238
        }
    }

    /// Stronger beams consume more battery per second.
    var drainPerSecond: CGFloat {
        switch self {
        case .flash: return 0.20
        case .steady: return 0.48
        case .strong: return 0.92
        }
    }

    var beamColor: UIColor {
        switch self {
        case .flash: return UIColor(red: 0.77, green: 0.88, blue: 0.91, alpha: 1)
        case .steady: return UIColor(red: 0.96, green: 0.91, blue: 0.72, alpha: 1)
        case .strong: return UIColor(red: 1.00, green: 0.84, blue: 0.56, alpha: 1)
        }
    }
}

/// Owns flashlight state and battery. Battery is clamped to 0...100 and an empty
/// battery always forces the flashlight off.
final class FlashlightSystem {
    private(set) var batteryPercent: CGFloat = 100
    private(set) var level: FlashlightLevel = .steady
    private(set) var isOn = true

    func toggle() {
        guard batteryPercent > 0 else {
            isOn = false
            return
        }
        isOn.toggle()
    }

    func cycleLevel() {
        guard let index = FlashlightLevel.allCases.firstIndex(of: level) else { return }
        level = FlashlightLevel.allCases[(index + 1) % FlashlightLevel.allCases.count]
    }

    func restore(batteryPercent: CGFloat, level: FlashlightLevel, isOn: Bool) {
        self.batteryPercent = min(max(batteryPercent, 0), 100)
        self.level = level
        self.isOn = isOn && self.batteryPercent > 0
    }

    func sacrifice() {
        batteryPercent = 0
        isOn = false
    }

    func update(delta: TimeInterval) {
        guard isOn, batteryPercent > 0, delta > 0 else { return }
        batteryPercent = max(0, batteryPercent - level.drainPerSecond * CGFloat(delta))
        if batteryPercent <= 0 {
            batteryPercent = 0
            isOn = false
        }
    }
}

/// A placed, already-lit flare. The flare is a temporary light source and a
/// Demogorgon lure; it does not reveal the player to the sound-hunting Death Angel.
final class LitFlare: SKNode {
    let burnDuration: TimeInterval = 22
    private(set) var remainingTime: TimeInterval = 22
    private let scaleFactor: CGFloat
    private let halo: SKShapeNode

    init(scaleFactor: CGFloat) {
        self.scaleFactor = scaleFactor
        halo = SKShapeNode(circleOfRadius: 48 * scaleFactor)
        super.init()
        name = "litFlare"
        zPosition = 8

        halo.fillColor = UIColor(red: 1, green: 0.31, blue: 0.075, alpha: 0.16)
        halo.strokeColor = UIColor(red: 1, green: 0.49, blue: 0.13, alpha: 0.75)
        halo.lineWidth = 1.5 * scaleFactor
        halo.glowWidth = 17 * scaleFactor
        addChild(halo)

        let ember = SKShapeNode(circleOfRadius: 6 * scaleFactor)
        ember.fillColor = UIColor(red: 1, green: 0.68, blue: 0.22, alpha: 1)
        ember.strokeColor = UIColor(red: 1, green: 0.90, blue: 0.56, alpha: 1)
        ember.lineWidth = 1.5 * scaleFactor
        ember.glowWidth = 10 * scaleFactor
        ember.zPosition = 1
        addChild(ember)
    }

    required init?(coder: NSCoder) {
        fatalError("LitFlare is created in code.")
    }

    @discardableResult
    func advance(delta: TimeInterval) -> Bool {
        remainingTime = max(0, remainingTime - max(0, delta))
        let pulse = 0.88 + 0.12 * CGFloat(sin((burnDuration - remainingTime) * 5.2))
        halo.setScale(pulse)
        halo.alpha = remainingTime < 4 ? 0.48 + 0.52 * CGFloat(abs(sin((burnDuration - remainingTime) * 8))) : 1
        return remainingTime <= 0
    }
}
