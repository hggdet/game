import SpriteKit
import UIKit

/// Shared run/light-use memory. A zone becomes a habitual route after three
/// deliberate uses; both hunters consult the same memory during patrol.
final class MonsterMemory {
    private(set) var useCounts: [String: Int] = [:]
    private var zoneCenters: [String: CGPoint] = [:]
    private(set) var favoredZoneID: String?

    func registerZone(_ id: String, center: CGPoint) {
        zoneCenters[id] = center
    }

    func recordUse(in zoneID: String) {
        guard zoneCenters[zoneID] != nil else { return }
        useCounts[zoneID, default: 0] += 1
        guard useCounts[zoneID, default: 0] >= 3 else { return }
        if let current = favoredZoneID, useCounts[current, default: 0] > useCounts[zoneID, default: 0] {
            return
        }
        favoredZoneID = zoneID
    }

    func favoredPoint() -> CGPoint? {
        guard let favoredZoneID else { return nil }
        return zoneCenters[favoredZoneID]
    }
}

/// Sound-only hunter. It remembers the origin of the loudest recent event and
/// never reads the player's live location.
final class DeathAngelAI: SKNode {
    private(set) var state: DeathAngelState = .patrol
    private(set) var lastKnownPosition = CGPoint.zero
    private(set) var hasLastKnownPosition = false
    var onStateChange: ((DeathAngelState) -> Void)?
    private(set) var isActive = false

    private let scaleFactor: CGFloat
    private let patrolPoints: [CGPoint]
    private let hidingSpots: [CGPoint]
    private let memory: MonsterMemory
    private let bodySprite = SKSpriteNode(imageNamed: "DeathAngel")
    private var patrolIndex = 0
    private var searchTargets: [CGPoint] = []
    private var searchTargetIndex = 0
    private var searchWait: TimeInterval = 0
    private var worldClock: TimeInterval = 0
    private var patrolHoldElapsed: TimeInterval = 0
    var isInDeadlyCorridor = false

    init(scaleFactor: CGFloat, patrolPoints: [CGPoint], hidingSpots: [CGPoint], memory: MonsterMemory) {
        self.scaleFactor = scaleFactor
        self.patrolPoints = patrolPoints
        self.hidingSpots = hidingSpots
        self.memory = memory
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
        setActive(false)
    }

    required init?(coder: NSCoder) {
        fatalError("DeathAngelAI is created in code.")
    }

    func setActive(_ active: Bool) {
        let wasActive = isActive
        isActive = active
        isHidden = !active
        physicsBody?.collisionBitMask = active ? PhysicsCategory.wall : 0
        if !active { physicsBody?.velocity = .zero }
        if active && !wasActive {
            if state == .chase {
                AudioManager.play(.deathAngelScreech, at: position)
            } else if state == .investigate {
                AudioManager.play(.deathAngelBreath, at: position)
            }
        }
    }

    func hear(_ event: NoiseEvent) {
        let distance = pointDistance(event.position, position)
        guard event.radius > 0, distance <= event.radius else { return }
        lastKnownPosition = event.position
        hasLastKnownPosition = true
        searchWait = 0

        let loudSources: Set<NoiseSource> = [.runningFootstep, .glassBreak, .thrownItem, .loudPickup]
        let isLoud = loudSources.contains(event.source) || event.radius >= 255 * scaleFactor
        if isLoud {
            setState(.chase)
        } else if state != .chase {
            setState(.investigate)
        }
    }

    func advance(delta: TimeInterval) {
        worldClock += delta
        guard isActive, let physicsBody else {
            physicsBody?.velocity = .zero
            return
        }

        switch state {
        case .patrol:
            advancePatrol(delta: delta)
        case .investigate:
            guard hasLastKnownPosition else { setState(.patrol); return }
            move(toward: lastKnownPosition, speed: 58 * scaleFactor)
            if pointDistance(position, lastKnownPosition) < 14 * scaleFactor {
                beginSearch()
            }
        case .chase:
            guard hasLastKnownPosition else { setState(.patrol); return }
            let corridorMultiplier: CGFloat = isInDeadlyCorridor ? 1.72 : 1
            move(toward: lastKnownPosition, speed: 122 * scaleFactor * corridorMultiplier)
            if pointDistance(position, lastKnownPosition) < 15 * scaleFactor {
                beginSearch()
            }
        case .search:
            advanceSearch(delta: delta)
        }
    }

    private func advancePatrol(delta: TimeInterval) {
        if let favorite = memory.favoredPoint() {
            patrolHoldElapsed += delta
            if pointDistance(position, favorite) > 15 * scaleFactor {
                move(toward: favorite, speed: 34 * scaleFactor)
            } else {
                physicsBody?.velocity = .zero
                if patrolHoldElapsed >= 2.8 { patrolHoldElapsed = 0 }
            }
            return
        }
        guard !patrolPoints.isEmpty else { physicsBody?.velocity = .zero; return }
        let target = patrolPoints[patrolIndex % patrolPoints.count]
        move(toward: target, speed: 36 * scaleFactor)
        if pointDistance(position, target) < 12 * scaleFactor {
            patrolIndex = (patrolIndex + 1) % patrolPoints.count
        }
    }

    private func beginSearch() {
        searchTargets = [lastKnownPosition]
        let nearbyLockers = hidingSpots
            .filter { pointDistance($0, lastKnownPosition) <= 260 * scaleFactor }
            .sorted { pointDistance($0, lastKnownPosition) < pointDistance($1, lastKnownPosition) }
        searchTargets.append(contentsOf: nearbyLockers)
        searchTargetIndex = 0
        searchWait = 0
        setState(.search)
    }

    private func advanceSearch(delta: TimeInterval) {
        guard searchTargetIndex < searchTargets.count else {
            setState(.patrol)
            return
        }
        let target = searchTargets[searchTargetIndex]
        if pointDistance(position, target) > 12 * scaleFactor {
            move(toward: target, speed: 34 * scaleFactor)
        } else {
            physicsBody?.velocity = .zero
            searchWait += delta
            if searchWait >= 0.72 {
                searchWait = 0
                searchTargetIndex += 1
                if searchTargetIndex >= searchTargets.count { setState(.patrol) }
            }
        }
    }

    private func move(toward target: CGPoint, speed: CGFloat) {
        let dx = target.x - position.x
        let dy = target.y - position.y
        let length = hypot(dx, dy)
        guard length > 1 else { physicsBody?.velocity = .zero; return }
        physicsBody?.velocity = CGVector(dx: dx / length * speed, dy: dy / length * speed)
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
            if isActive { AudioManager.play(.deathAngelBreath, at: position) }
        case .chase:
            bodySprite.color = UIColor(red: 0.91, green: 0.32, blue: 0.28, alpha: 1)
            bodySprite.colorBlendFactor = 0.36
            if isActive { AudioManager.play(.deathAngelScreech, at: position) }
        case .search:
            bodySprite.color = UIColor(red: 0.86, green: 0.72, blue: 0.42, alpha: 1)
            bodySprite.colorBlendFactor = 0.20
        }
    }
}

/// Sight/light hunter. It observes the player's position only when the player is
/// illuminated (or physically adjacent in darkness) and otherwise follows its
/// last seen light position or an active flare, never the live hidden position.
final class DemogorgonAI: SKNode {
    private(set) var state: DemogorgonState = .patrol
    private(set) var lastKnownPosition = CGPoint.zero
    private(set) var hasLastKnownPosition = false
    var onStateChange: ((DemogorgonState) -> Void)?
    private(set) var isActive = false
    var isInWeakCorridor = false

    private let scaleFactor: CGFloat
    private let patrolPoints: [CGPoint]
    private let hidingSpots: [CGPoint]
    private let memory: MonsterMemory
    private let bodySprite = SKSpriteNode(imageNamed: "Demogorgon")
    private var patrolIndex = 0
    private var searchTargets: [CGPoint] = []
    private var searchTargetIndex = 0
    private var searchWait: TimeInterval = 0
    private var worldClock: TimeInterval = 0
    private var lostSightElapsed: TimeInterval = 0
    private var flareTarget: CGPoint?

    init(scaleFactor: CGFloat, patrolPoints: [CGPoint], hidingSpots: [CGPoint], memory: MonsterMemory) {
        self.scaleFactor = scaleFactor
        self.patrolPoints = patrolPoints
        self.hidingSpots = hidingSpots
        self.memory = memory
        super.init()
        name = "demogorgon"
        zPosition = 10

        let aura = SKShapeNode(circleOfRadius: 31 * scaleFactor)
        aura.fillColor = UIColor(red: 0.54, green: 0.10, blue: 0.09, alpha: 0.10)
        aura.strokeColor = UIColor(red: 0.89, green: 0.31, blue: 0.20, alpha: 0.70)
        aura.lineWidth = 1.4 * scaleFactor
        aura.glowWidth = 12 * scaleFactor
        addChild(aura)

        bodySprite.size = CGSize(width: 57 * scaleFactor, height: 58 * scaleFactor)
        bodySprite.anchorPoint = CGPoint(x: 0.5, y: 0.46)
        bodySprite.zPosition = 1
        addChild(bodySprite)

        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = "DEMOGORGON"
        label.fontSize = 7 * scaleFactor
        label.fontColor = UIColor(white: 0.96, alpha: 0.93)
        label.position = CGPoint(x: 0, y: -39 * scaleFactor)
        label.zPosition = 2
        addChild(label)

        let body = SKPhysicsBody(circleOfRadius: 20 * scaleFactor)
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
        setActive(false)
    }

    required init?(coder: NSCoder) {
        fatalError("DemogorgonAI is created in code.")
    }

    func setActive(_ active: Bool) {
        let wasActive = isActive
        isActive = active
        isHidden = !active
        physicsBody?.collisionBitMask = active ? PhysicsCategory.wall : 0
        if !active { physicsBody?.velocity = .zero }
        if active && !wasActive && state == .chase {
            AudioManager.play(.demogorgonGrowl, at: position)
        }
    }

    /// A hidden player is omitted from sight checks. The Demogorgon may still
    /// investigate its previous sighting or a flare, but it cannot acquire the
    /// current locker position by looking at the player.
    func observe(
        playerPosition: CGPoint,
        flashlightOn: Bool,
        level: FlashlightLevel,
        flarePosition: CGPoint?,
        time: TimeInterval,
        playerHidden: Bool = false
    ) {
        if !playerHidden {
            let playerDistance = pointDistance(position, playerPosition)
            let isAdjacentInDarkness = playerDistance <= 27 * scaleFactor
            let isSeenInLight = flashlightOn && playerDistance <= level.detectionRange * scaleFactor

            if isAdjacentInDarkness || isSeenInLight {
                lastKnownPosition = playerPosition
                hasLastKnownPosition = true
                lostSightElapsed = 0
                flareTarget = nil
                setState(.chase)
                return
            }
        }

        if let flarePosition, pointDistance(position, flarePosition) <= 520 * scaleFactor {
            flareTarget = flarePosition
            lastKnownPosition = flarePosition
            hasLastKnownPosition = true
            lostSightElapsed = 0
            if state != .chase { setState(.investigate) }
            return
        }

        flareTarget = nil
        if state == .chase {
            lostSightElapsed += max(0, time)
            if lostSightElapsed > 0.78 {
                lostSightElapsed = 0
                setState(.investigate)
            }
        }
    }

    func advance(delta: TimeInterval) {
        worldClock += delta
        guard isActive, let physicsBody else {
            physicsBody?.velocity = .zero
            return
        }

        switch state {
        case .patrol:
            advancePatrol(delta: delta)
        case .investigate:
            guard let target = flareTarget ?? (hasLastKnownPosition ? lastKnownPosition : nil) else {
                setState(.patrol)
                return
            }
            move(toward: target, speed: 48 * scaleFactor)
            if pointDistance(position, target) < 15 * scaleFactor, flareTarget == nil {
                beginSearch()
            }
        case .chase:
            guard hasLastKnownPosition else { setState(.patrol); return }
            let corridorMultiplier: CGFloat = isInWeakCorridor ? 0.68 : 1
            move(toward: lastKnownPosition, speed: 73 * scaleFactor * corridorMultiplier)
            if pointDistance(position, lastKnownPosition) < 13 * scaleFactor {
                beginSearch()
            }
        case .search:
            advanceSearch(delta: delta)
        }
    }

    private func advancePatrol(delta: TimeInterval) {
        if let favorite = memory.favoredPoint() {
            searchWait += delta
            if pointDistance(position, favorite) > 15 * scaleFactor {
                move(toward: favorite, speed: 31 * scaleFactor)
            } else {
                physicsBody?.velocity = .zero
                if searchWait >= 2.8 { searchWait = 0 }
            }
            return
        }
        guard !patrolPoints.isEmpty else { physicsBody?.velocity = .zero; return }
        let target = patrolPoints[patrolIndex % patrolPoints.count]
        move(toward: target, speed: 31 * scaleFactor)
        if pointDistance(position, target) < 12 * scaleFactor {
            patrolIndex = (patrolIndex + 1) % patrolPoints.count
        }
    }

    private func beginSearch() {
        searchTargets = [hasLastKnownPosition ? lastKnownPosition : position]
        let nearbyLockers = hidingSpots
            .filter { pointDistance($0, lastKnownPosition) <= 260 * scaleFactor }
            .sorted { pointDistance($0, lastKnownPosition) < pointDistance($1, lastKnownPosition) }
        searchTargets.append(contentsOf: nearbyLockers)
        searchTargetIndex = 0
        searchWait = 0
        flareTarget = nil
        setState(.search)
    }

    private func advanceSearch(delta: TimeInterval) {
        guard searchTargetIndex < searchTargets.count else {
            setState(.patrol)
            return
        }
        let target = searchTargets[searchTargetIndex]
        if pointDistance(position, target) > 12 * scaleFactor {
            move(toward: target, speed: 31 * scaleFactor)
        } else {
            physicsBody?.velocity = .zero
            searchWait += delta
            if searchWait >= 0.68 {
                searchWait = 0
                searchTargetIndex += 1
                if searchTargetIndex >= searchTargets.count { setState(.patrol) }
            }
        }
    }

    private func move(toward target: CGPoint, speed: CGFloat) {
        let dx = target.x - position.x
        let dy = target.y - position.y
        let length = hypot(dx, dy)
        guard length > 1 else { physicsBody?.velocity = .zero; return }
        physicsBody?.velocity = CGVector(dx: dx / length * speed, dy: dy / length * speed)
    }

    private func setState(_ newState: DemogorgonState) {
        guard state != newState else { return }
        state = newState
        onStateChange?(newState)
        switch newState {
        case .patrol:
            bodySprite.color = .white
            bodySprite.colorBlendFactor = 0
        case .investigate:
            bodySprite.color = UIColor(red: 0.84, green: 0.45, blue: 0.27, alpha: 1)
            bodySprite.colorBlendFactor = 0.18
        case .chase:
            bodySprite.color = UIColor(red: 0.96, green: 0.19, blue: 0.12, alpha: 1)
            bodySprite.colorBlendFactor = 0.42
            if isActive { AudioManager.play(.demogorgonGrowl, at: position) }
        case .search:
            bodySprite.color = UIColor(red: 0.86, green: 0.66, blue: 0.38, alpha: 1)
            bodySprite.colorBlendFactor = 0.20
        }
    }
}

private func pointDistance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
    hypot(lhs.x - rhs.x, lhs.y - rhs.y)
}
