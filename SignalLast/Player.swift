import SpriteKit
import UIKit

/// Shared physics categories for the player, hunter, and room walls.
enum PhysicsCategory {
    static let player: UInt32 = 1 << 0
    static let hunter: UInt32 = 1 << 1
    static let wall: UInt32 = 1 << 2
}

final class Player: SKShapeNode {
    private(set) var speedMode: PlayerSpeed = .idle
    var movementInput = CGVector.zero
    var sprintRequested = false

    private let scaleFactor: CGFloat
    private var footstepClock: TimeInterval = 0

    init(scaleFactor: CGFloat) {
        self.scaleFactor = scaleFactor
        super.init(circleOfRadius: 9 * scaleFactor)

        fillColor = UIColor(red: 0.28, green: 0.84, blue: 0.91, alpha: 1)
        strokeColor = UIColor(red: 0.82, green: 0.98, blue: 1, alpha: 1)
        lineWidth = 1.5 * scaleFactor
        glowWidth = 7 * scaleFactor
        zPosition = 12
        name = "player"

        let core = SKShapeNode(circleOfRadius: 2.6 * scaleFactor)
        core.fillColor = UIColor(red: 0.04, green: 0.18, blue: 0.23, alpha: 1)
        core.strokeColor = .clear
        addChild(core)

        let body = SKPhysicsBody(circleOfRadius: 8 * scaleFactor)
        body.isDynamic = true
        body.affectedByGravity = false
        body.allowsRotation = false
        body.linearDamping = 0
        body.friction = 0
        body.restitution = 0
        body.categoryBitMask = PhysicsCategory.player
        body.collisionBitMask = PhysicsCategory.wall
        body.contactTestBitMask = 0
        physicsBody = body
    }

    required init?(coder: NSCoder) {
        fatalError("Player is created in code.")
    }

    func updateMovement(delta: TimeInterval, surface: NoiseSurface, noiseSystem: NoiseSystem, sceneTime: TimeInterval) {
        let inputLength = sqrt(movementInput.dx * movementInput.dx + movementInput.dy * movementInput.dy)
        guard inputLength >= 0.12 else {
            speedMode = .idle
            footstepClock = 0
            physicsBody?.velocity = .zero
            return
        }

        if sprintRequested {
            speedMode = .run
        } else if inputLength < 0.58 {
            speedMode = .sneak
        } else {
            speedMode = .walk
        }

        let direction = CGVector(dx: movementInput.dx / inputLength, dy: movementInput.dy / inputLength)
        let speed: CGFloat
        switch speedMode {
        case .idle:
            speed = 0
        case .sneak:
            speed = 42 * scaleFactor
        case .walk:
            speed = 82 * scaleFactor
        case .run:
            speed = 150 * scaleFactor
        }
        physicsBody?.velocity = CGVector(dx: direction.dx * speed, dy: direction.dy * speed)

        guard speedMode == .walk || speedMode == .run else {
            footstepClock = 0
            return
        }

        footstepClock += delta
        let interval: TimeInterval = speedMode == .run ? 0.25 : 0.43
        guard footstepClock >= interval else { return }
        footstepClock -= interval

        let baseRadius: CGFloat = speedMode == .run ? 300 * scaleFactor : 115 * scaleFactor
        let source: NoiseSource = speedMode == .run ? .runningFootstep : .footstep
        noiseSystem.emit(source: source, at: position, baseRadius: baseRadius, surface: surface, time: sceneTime)
        AudioManager.play(.playerFootstep)
    }
}
