import SpriteKit
import UIKit

/// A collectible signal fragment. The value is assigned by GameScene from its
/// distance to the hunters' patrol routes; noisy pickups emit a separate event.
final class CollectiblePart: SKNode {
    let index: Int
    let pointValue: Int
    let isNoisy: Bool

    init(index: Int, pointValue: Int, isNoisy: Bool, scaleFactor: CGFloat) {
        self.index = index
        self.pointValue = pointValue
        self.isNoisy = isNoisy
        super.init()
        name = "collectiblePart-\(index)"
        zPosition = 13

        let halo = SKShapeNode(circleOfRadius: 13 * scaleFactor)
        halo.fillColor = UIColor(red: 0.12, green: 0.72, blue: 0.80, alpha: 0.13)
        halo.strokeColor = UIColor(red: 0.32, green: 0.89, blue: 0.94, alpha: 0.54)
        halo.lineWidth = 1 * scaleFactor
        halo.glowWidth = 7 * scaleFactor
        addChild(halo)
        halo.run(.repeatForever(.sequence([
            .scale(to: 1.15, duration: 0.48),
            .scale(to: 0.88, duration: 0.48)
        ])))

        let shard = SKShapeNode(rectOf: CGSize(width: 11 * scaleFactor, height: 14 * scaleFactor), cornerRadius: 2 * scaleFactor)
        shard.fillColor = isNoisy
            ? UIColor(red: 0.93, green: 0.60, blue: 0.27, alpha: 1)
            : UIColor(red: 0.43, green: 0.91, blue: 0.91, alpha: 1)
        shard.strokeColor = UIColor(white: 0.97, alpha: 0.94)
        shard.lineWidth = 1 * scaleFactor
        shard.glowWidth = 4 * scaleFactor
        shard.zRotation = .pi / 4
        addChild(shard)

        let valueLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        valueLabel.text = "+\(pointValue)"
        valueLabel.fontSize = 6.5 * scaleFactor
        valueLabel.fontColor = UIColor(white: 0.96, alpha: 0.92)
        valueLabel.verticalAlignmentMode = .center
        valueLabel.horizontalAlignmentMode = .center
        valueLabel.position = CGPoint(x: 0, y: -18 * scaleFactor)
        valueLabel.zPosition = 1
        addChild(valueLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("CollectiblePart is created in code.")
    }
}

/// The single survivor rescued by the player. While following, the NPC walks
/// behind the player and periodically reports footstep noise to GameScene.
final class SurvivorNPC: SKNode {
    private(set) var isFollowing = false
    private let scaleFactor: CGFloat
    private var footstepClock: TimeInterval = 0

    init(scaleFactor: CGFloat) {
        self.scaleFactor = scaleFactor
        super.init()
        name = "survivor"
        zPosition = 11

        let aura = SKShapeNode(circleOfRadius: 14 * scaleFactor)
        aura.fillColor = UIColor(red: 0.82, green: 0.69, blue: 0.35, alpha: 0.10)
        aura.strokeColor = UIColor(red: 0.96, green: 0.79, blue: 0.42, alpha: 0.66)
        aura.lineWidth = 1 * scaleFactor
        aura.glowWidth = 5 * scaleFactor
        addChild(aura)

        let bodyShape = SKShapeNode(circleOfRadius: 8 * scaleFactor)
        bodyShape.fillColor = UIColor(red: 0.76, green: 0.67, blue: 0.48, alpha: 1)
        bodyShape.strokeColor = UIColor(red: 1, green: 0.91, blue: 0.67, alpha: 0.96)
        bodyShape.lineWidth = 1.3 * scaleFactor
        bodyShape.glowWidth = 3 * scaleFactor
        addChild(bodyShape)

        let cross = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -3.5 * scaleFactor, y: 0))
        path.addLine(to: CGPoint(x: 3.5 * scaleFactor, y: 0))
        path.move(to: CGPoint(x: 0, y: -3.5 * scaleFactor))
        path.addLine(to: CGPoint(x: 0, y: 3.5 * scaleFactor))
        cross.path = path
        cross.strokeColor = UIColor(red: 0.18, green: 0.23, blue: 0.25, alpha: 1)
        cross.lineWidth = 1.3 * scaleFactor
        cross.zPosition = 1
        addChild(cross)

        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = "ناجٍ"
        label.fontSize = 7 * scaleFactor
        label.fontColor = UIColor(white: 0.97, alpha: 0.92)
        label.position = CGPoint(x: 0, y: -19 * scaleFactor)
        label.zPosition = 2
        addChild(label)

        let body = SKPhysicsBody(circleOfRadius: 7 * scaleFactor)
        body.isDynamic = true
        body.affectedByGravity = false
        body.allowsRotation = false
        body.linearDamping = 0
        body.friction = 0
        body.restitution = 0
        body.categoryBitMask = PhysicsCategory.companion
        body.collisionBitMask = PhysicsCategory.wall
        body.contactTestBitMask = 0
        physicsBody = body
    }

    required init?(coder: NSCoder) {
        fatalError("SurvivorNPC is created in code.")
    }

    func beginFollowing() {
        isFollowing = true
        footstepClock = 0
        children.compactMap { $0 as? SKShapeNode }.first?.strokeColor = UIColor(red: 1, green: 0.83, blue: 0.38, alpha: 1)
    }

    /// Returns true once per footstep interval while the survivor is walking.
    @discardableResult
    func advance(delta: TimeInterval, following playerPosition: CGPoint) -> Bool {
        guard isFollowing, let physicsBody else {
            physicsBody?.velocity = .zero
            return false
        }
        let dx = playerPosition.x - position.x
        let dy = playerPosition.y - position.y
        let distance = hypot(dx, dy)
        let followDistance = 27 * scaleFactor
        guard distance > followDistance else {
            physicsBody.velocity = .zero
            return false
        }

        let speed = 75 * scaleFactor
        physicsBody.velocity = CGVector(dx: dx / distance * speed, dy: dy / distance * speed)
        footstepClock += max(0, delta)
        guard footstepClock >= 1.35 else { return false }
        footstepClock -= 1.35
        return true
    }
}
