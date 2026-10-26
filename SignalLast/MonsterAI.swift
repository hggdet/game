import SpriteKit

/// Phase 1's only hunter. It reacts to emitted noise events and never reads the player's live position.
final class DeathAngelAI: SKNode {
    private(set) var state: DeathAngelState = .patrol
    var onStateChange: ((DeathAngelState) -> Void)?

    private let scaleFactor: CGFloat
    private let patrolPoints: [CGPoint]
    private let bodySprite = SKSpriteNode(imageNamed: "DeathAngel")
    private var patrolIndex = 0
    private var lastHeardPosition = CGPoint.zero
    private var searchElapsed: TimeInterval = 0
    private var worldClock: TimeInterval = 0

    init(scaleFactor: CGFloat, patrolPoints: [CGPoint]) {
        self.scaleFactor = scaleFactor
        self.patrolPoints = patrolPoints
        super.init()

        name = "deathAngel"
        zPosition = 11

        let aura = SKShapeNode(circleOfRadius: 24 * scaleFactor)
        aura.fillColor = UIColor(red: 0.46, green: 0.69, blue: 0.84, alpha: 0.10)
        aura.strokeColor = UIColor(red: 0.49, green: 0.78, blue: 0.91, alpha: 0.78)
        aura.lineWidth = 1.3 * scaleFactor
        aura.glowWidth = 9 * scaleFactor
        addChild(aura)

        bodySprite.size = CGSize(width: 49 * scaleFactor, height: 51 * scaleFactor)
        bodySprite.anchorPoint = CGPoint(x: 0.5, y: 0.47)
        bodySprite.zPosition = 1
        addChild(bodySprite)

        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = "DEATH ANGEL"
        label.fontSize = 7 * scaleFactor
        label.fontColor = UIColor(white: 0.91, alpha: 0.92)
        label.position = CGPoint(x: 0, y: -35 * scaleFactor)
        label.zPosition = 2
        addChild(label)

        let body = SKPhysicsBody(circleOfRadius: 18 * scaleFactor)
        body.isDynamic = true
        body.affectedByGravity = false
        body.allowsRotation = false
        body.linearDamping = 0
        body.friction = 0
        body.restitution = 0
        body.categoryBitMask = PhysicsCategory.hunter
        body.collisionBitMask = PhysicsCategory.wall
        body.contactTestBitMask = 0
        physicsBody = body
    }

    required init?(coder: NSCoder) {
        fatalError("DeathAngelAI is created in code.")
    }

    func hear(_ event: NoiseEvent) {
        let dx = event.position.x - position.x
        let dy = event.position.y - position.y
        guard event.radius > 0, sqrt(dx * dx + dy * dy) <= event.radius else { return }

        lastHeardPosition = event.position
        searchElapsed = 0

        let isLoud = event.source == .runningFootstep || event.source == .glassBreak || event.source == .thrownItem || event.source == .loudPickup || event.radius >= 255 * scaleFactor
        if isLoud {
            setState(.chase)
        } else if state != .chase {
            setState(.investigate)
        }
    }

    func advance(delta: TimeInterval) {
        worldClock += delta
        guard let physicsBody else { return }

        switch state {
        case .patrol:
            guard !patrolPoints.isEmpty else {
                physicsBody.velocity = .zero
                return
            }
            let target = patrolPoints[patrolIndex % patrolPoints.count]
            move(toward: target, speed: 36 * scaleFactor)
            if distance(from: position, to: target) < 12 * scaleFactor {
                patrolIndex = (patrolIndex + 1) % patrolPoints.count
            }

        case .investigate:
            move(toward: lastHeardPosition, speed: 66 * scaleFactor)
            if distance(from: position, to: lastHeardPosition) < 14 * scaleFactor {
                searchElapsed = 0
                setState(.search)
            }

        case .chase:
            move(toward: lastHeardPosition, speed: 122 * scaleFactor)
            if distance(from: position, to: lastHeardPosition) < 16 * scaleFactor {
                searchElapsed = 0
                setState(.search)
            }

        case .search:
            searchElapsed += delta
            let radius = 24 * scaleFactor
            let angle = worldClock * 2.4
            let offsetX = CGFloat(cos(angle)) * radius
            let offsetY = CGFloat(sin(angle)) * radius
            let target = CGPoint(x: lastHeardPosition.x + offsetX, y: lastHeardPosition.y + offsetY)
            move(toward: target, speed: 43 * scaleFactor)
            if searchElapsed >= 4.5 {
                setState(.patrol)
            }
        }
    }

    private func move(toward target: CGPoint, speed: CGFloat) {
        let dx = target.x - position.x
        let dy = target.y - position.y
        let length = hypot(dx, dy)
        guard length > 1 else {
            physicsBody?.velocity = .zero
            return
        }
        physicsBody?.velocity = CGVector(dx: dx / length * speed, dy: dy / length * speed)
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return sqrt(dx * dx + dy * dy)
    }

    private func setState(_ newState: DeathAngelState) {
        guard state != newState else { return }
        state = newState
        onStateChange?(newState)

        switch newState {
        case .patrol:
            bodySprite.color = .white
            bodySprite.colorBlendFactor = 0
        case .investigate:
            bodySprite.color = UIColor(red: 0.48, green: 0.77, blue: 0.91, alpha: 1)
            bodySprite.colorBlendFactor = 0.22
            AudioManager.play(.deathAngelBreath)
        case .chase:
            bodySprite.color = UIColor(red: 0.91, green: 0.32, blue: 0.28, alpha: 1)
            bodySprite.colorBlendFactor = 0.36
            AudioManager.play(.deathAngelScreech)
        case .search:
            bodySprite.color = UIColor(red: 0.86, green: 0.72, blue: 0.42, alpha: 1)
            bodySprite.colorBlendFactor = 0.20
        }
    }
}
