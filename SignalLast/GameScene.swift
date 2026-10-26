import SpriteKit
import UIKit

final class GameScene: SKScene {
    var onSnapshot: ((GameSnapshot) -> Void)?

    private var scaleFactor: CGFloat = 1
    private var roomBounds = CGRect.zero
    private var carpetRect = CGRect.zero
    private var glassRect = CGRect.zero
    private var glassBroken = false
    private var hasBuiltWorld = false
    private var lastUpdateTime: TimeInterval = 0
    private var publishClock: TimeInterval = 0
    private var sceneClock: TimeInterval = 0

    private var player: Player!
    private var deathAngel: DeathAngelAI!
    private var noiseSystem = NoiseSystem()

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0.012, green: 0.022, blue: 0.033, alpha: 1)
        physicsWorld.gravity = .zero
        physicsWorld.speed = 1
        if !hasBuiltWorld {
            buildWorld()
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard hasBuiltWorld, oldSize != .zero else { return }
        buildWorld()
    }

    func setMovementInput(_ input: CGVector) {
        player?.movementInput = input
    }

    func setSprintActive(_ isActive: Bool) {
        player?.sprintRequested = isActive
    }

    func restart() {
        buildWorld()
    }

    func publishSnapshotNow() {
        publishSnapshot()
    }

    override func update(_ currentTime: TimeInterval) {
        let delta: TimeInterval
        if lastUpdateTime == 0 {
            delta = 0
        } else {
            delta = min(max(currentTime - lastUpdateTime, 0), 0.08)
        }
        lastUpdateTime = currentTime
        sceneClock = currentTime

        guard hasBuiltWorld, let player, let deathAngel else { return }

        let currentSurface = surface(at: player.position)
        player.updateMovement(delta: delta, surface: currentSurface, noiseSystem: noiseSystem, sceneTime: currentTime)
        deathAngel.advance(delta: delta)
        checkGlass(at: player.position, time: currentTime)

        publishClock += delta
        if publishClock >= 0.16 {
            publishClock = 0
            publishSnapshot()
        }
    }

    private func buildWorld() {
        removeAllChildren()
        physicsWorld.removeAllJoints()
        physicsWorld.gravity = .zero

        let safeWidth = max(size.width, 320)
        let safeHeight = max(size.height, 600)
        scaleFactor = min(safeWidth / 390, safeHeight / 844)
        roomBounds = CGRect(
            x: size.width * 0.085,
            y: size.height * 0.155,
            width: size.width * 0.83,
            height: size.height * 0.70
        )
        carpetRect = CGRect(
            x: roomBounds.minX + roomBounds.width * 0.06,
            y: roomBounds.minY + roomBounds.height * 0.34,
            width: roomBounds.width * 0.29,
            height: roomBounds.height * 0.23
        )
        glassRect = CGRect(
            x: roomBounds.minX + roomBounds.width * 0.62,
            y: roomBounds.minY + roomBounds.height * 0.70,
            width: roomBounds.width * 0.29,
            height: roomBounds.height * 0.20
        )
        glassBroken = false
        lastUpdateTime = 0
        publishClock = 0
        sceneClock = 0
        noiseSystem = NoiseSystem()

        drawRoom()
        addRoomWalls()
        addSurfaceZone(carpetRect, title: "سجاد · هادئ", color: UIColor(red: 0.20, green: 0.31, blue: 0.33, alpha: 0.55))
        addSurfaceZone(glassRect, title: "زجاج · خطر", color: UIColor(red: 0.28, green: 0.46, blue: 0.53, alpha: 0.46))

        let start = CGPoint(x: roomBounds.midX, y: roomBounds.minY + roomBounds.height * 0.12)
        player = Player(scaleFactor: scaleFactor)
        player.position = start
        addChild(player)

        let patrolPoints = [
            CGPoint(x: roomBounds.minX + roomBounds.width * 0.24, y: roomBounds.maxY - roomBounds.height * 0.13),
            CGPoint(x: roomBounds.maxX - roomBounds.width * 0.23, y: roomBounds.maxY - roomBounds.height * 0.16),
            CGPoint(x: roomBounds.maxX - roomBounds.width * 0.20, y: roomBounds.minY + roomBounds.height * 0.60),
            CGPoint(x: roomBounds.minX + roomBounds.width * 0.20, y: roomBounds.minY + roomBounds.height * 0.60)
        ]
        deathAngel = DeathAngelAI(scaleFactor: scaleFactor, patrolPoints: patrolPoints)
        deathAngel.position = CGPoint(x: roomBounds.midX, y: roomBounds.maxY - roomBounds.height * 0.12)
        deathAngel.onStateChange = { [weak self] _ in self?.publishSnapshot() }
        addChild(deathAngel)

        noiseSystem.onNoise = { [weak self] event in
            guard let self else { return }
            self.deathAngel.hear(event)
            self.publishSnapshot()
        }

        hasBuiltWorld = true
        publishSnapshot()
    }

    private func drawRoom() {
        let floor = SKShapeNode(rect: roomBounds, cornerRadius: 18 * scaleFactor)
        floor.fillColor = UIColor(red: 0.045, green: 0.072, blue: 0.086, alpha: 1)
        floor.strokeColor = UIColor(red: 0.27, green: 0.39, blue: 0.43, alpha: 0.88)
        floor.lineWidth = 2 * scaleFactor
        floor.zPosition = 0
        addChild(floor)

        for index in 1...9 {
            let y = roomBounds.minY + roomBounds.height * CGFloat(index) / 10
            let line = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: roomBounds.minX + 8 * scaleFactor, y: y))
            path.addLine(to: CGPoint(x: roomBounds.maxX - 8 * scaleFactor, y: y))
            line.path = path
            line.strokeColor = UIColor(white: 0.78, alpha: 0.045)
            line.lineWidth = 0.7 * scaleFactor
            line.zPosition = 1
            addChild(line)
        }

        let edge = SKNode()
        edge.physicsBody = SKPhysicsBody(edgeLoopFrom: roomBounds.insetBy(dx: 10 * scaleFactor, dy: 10 * scaleFactor))
        edge.physicsBody?.isDynamic = false
        edge.physicsBody?.categoryBitMask = PhysicsCategory.wall
        edge.physicsBody?.collisionBitMask = PhysicsCategory.player | PhysicsCategory.hunter
        edge.zPosition = 2
        addChild(edge)

        addLabel("ممرّ المحطة 09", at: CGPoint(x: roomBounds.midX, y: roomBounds.maxY - 24 * scaleFactor), size: 10 * scaleFactor, color: UIColor(white: 0.77, alpha: 0.70))
    }

    private func addRoomWalls() {
        let wallThickness = 8 * scaleFactor
        let upperY = roomBounds.minY + roomBounds.height * 0.67
        let lowerY = roomBounds.minY + roomBounds.height * 0.34
        let gapWidth = roomBounds.width * 0.30

        addWall(rect: CGRect(x: roomBounds.minX + 1, y: upperY, width: (roomBounds.width - gapWidth) / 2, height: wallThickness))
        addWall(rect: CGRect(x: roomBounds.midX + gapWidth / 2, y: upperY, width: (roomBounds.width - gapWidth) / 2 - 1, height: wallThickness))
        addWall(rect: CGRect(x: roomBounds.minX + 1, y: lowerY, width: roomBounds.width * 0.25, height: wallThickness))
        addWall(rect: CGRect(x: roomBounds.maxX - roomBounds.width * 0.25, y: lowerY, width: roomBounds.width * 0.25 - 1, height: wallThickness))

        let dividerWidth = 7 * scaleFactor
        addWall(rect: CGRect(x: roomBounds.minX + roomBounds.width * 0.34, y: roomBounds.minY + roomBounds.height * 0.12, width: dividerWidth, height: roomBounds.height * 0.20))
    }

    private func addWall(rect: CGRect) {
        let wall = SKShapeNode(rect: rect, cornerRadius: 2 * scaleFactor)
        wall.fillColor = UIColor(red: 0.18, green: 0.25, blue: 0.28, alpha: 1)
        wall.strokeColor = UIColor(red: 0.34, green: 0.45, blue: 0.48, alpha: 0.72)
        wall.lineWidth = 1 * scaleFactor
        wall.zPosition = 4
        wall.physicsBody = SKPhysicsBody(rectangleOf: rect.size, center: CGPoint(x: rect.midX, y: rect.midY))
        wall.physicsBody?.isDynamic = false
        wall.physicsBody?.categoryBitMask = PhysicsCategory.wall
        wall.physicsBody?.collisionBitMask = PhysicsCategory.player | PhysicsCategory.hunter
        addChild(wall)
    }

    private func addSurfaceZone(_ rect: CGRect, title: String, color: UIColor) {
        let zone = SKShapeNode(rect: rect, cornerRadius: 8 * scaleFactor)
        zone.fillColor = color
        zone.strokeColor = color.withAlphaComponent(0.85)
        zone.lineWidth = 1 * scaleFactor
        zone.zPosition = 2
        addChild(zone)
        addLabel(title, at: CGPoint(x: rect.midX, y: rect.midY), size: 7.5 * scaleFactor, color: UIColor(white: 0.92, alpha: 0.80))
    }

    private func addLabel(_ text: String, at position: CGPoint, size: CGFloat, color: UIColor) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Medium")
        label.text = text
        label.fontSize = size
        label.fontColor = color
        label.position = position
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 5
        addChild(label)
    }

    private func surface(at point: CGPoint) -> NoiseSurface {
        if glassRect.contains(point) { return .glass }
        if carpetRect.contains(point) { return .carpet }
        return .metal
    }

    private func checkGlass(at point: CGPoint, time: TimeInterval) {
        guard !glassBroken, glassRect.contains(point) else { return }
        glassBroken = true
        noiseSystem.emit(source: .glassBreak, at: point, baseRadius: 215 * scaleFactor, surface: .glass, time: time)
        AudioManager.play(.glassBreak)
    }

    private func publishSnapshot() {
        guard hasBuiltWorld, let player, let deathAngel else { return }
        let activeNoise = noiseSystem.latestEvent.flatMap { sceneClock - $0.timestamp < 3.0 ? $0 : nil }
        let intensity = min((activeNoise?.radius ?? 0) / (420 * scaleFactor), 1)

        let message: String
        switch deathAngel.state {
        case .patrol:
            message = "أنت في دوريته الآن. التسلّل لا يصدر ضوضاء."
        case .investigate:
            message = "سمع Death Angel حركةً ويتجه إلى مصدر الصوت."
        case .chase:
            message = "الصوت العالي لفت انتباهه؛ أوقف الضوضاء وغيّر موقعك."
        case .search:
            message = "يفتش حول آخر صوت سمعه؛ ابتعد بهدوء."
        }

        onSnapshot?(GameSnapshot(
            playerSpeed: player.speedMode,
            deathAngelState: deathAngel.state,
            surface: surface(at: player.position),
            noiseIntensity: intensity,
            statusMessage: message
        ))
    }
}
