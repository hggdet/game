import SpriteKit
import UIKit

final class GameScene: SKScene {
    var onSnapshot: ((GameSnapshot) -> Void)?
    var onProgress: ((GameState) -> Void)?

    private var scaleFactor: CGFloat = 1
    private var roomBounds = CGRect.zero
    private var carpetRect = CGRect.zero
    private var glassRect = CGRect.zero
    private var pitchDarkRoomRect = CGRect.zero
    private var narrowCorridorRect = CGRect.zero
    private var glassBroken = false
    private var hasBuiltWorld = false
    private var lastUpdateTime: TimeInterval = 0
    private var publishClock: TimeInterval = 0
    private var fogClock: TimeInterval = 0
    private var sceneClock: TimeInterval = 0
    private var habitClock: TimeInterval = 0
    private var lockerPositions: [CGPoint] = []
    private var activeLockerPosition: CGPoint?
    private var isHiding = false
    private var holdingBreath = false
    private var breathMeter: CGFloat = 0
    private var breathNoiseClock: TimeInterval = 0
    private var collectibleParts: [CollectiblePart] = []
    private var collectedPartIDs = Set<Int>()
    private var points = 0
    private var throwItemsRemaining = 3
    private var survivor: SurvivorNPC!
    private var survivorFollowing = false
    private var didFinish = false
    private var didLose = false
    private var isFinalChoicePending = false
    private var isWaitingInHiding = false
    private var hideWaitRemaining: TimeInterval = 30
    private var progressSaveClock: TimeInterval = 0
    private var gameState = GameState()
    private var exitPosition = CGPoint.zero
    private let heartbeat = HeartbeatHaptics()

    private var player: Player!
    private var deathAngel: DeathAngelAI!
    private var demogorgon: DemogorgonAI!
    private var noiseSystem = NoiseSystem()
    private var flashlight = FlashlightSystem()
    private var monsterMemory = MonsterMemory()
    private var monsterDirector = MonsterDirector()
    private var flare: LitFlare?
    private var sealedDoors: [SealedDoor] = []
    private var fogTiles: [FogTile] = []
    private var cameraNode: SKCameraNode!
    private var vignetteNode: SKShapeNode!

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0.006, green: 0.012, blue: 0.018, alpha: 1)
        physicsWorld.gravity = .zero
        physicsWorld.speed = 1
        if !hasBuiltWorld { buildWorld() }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard hasBuiltWorld, oldSize != .zero else { return }
        buildWorld()
    }

    func setMovementInput(_ input: CGVector) {
        player?.movementInput = (isHiding || didFinish || isFinalChoicePending) ? .zero : input
    }

    func setSprintActive(_ isActive: Bool) {
        player?.sprintRequested = isActive && !isHiding && !didFinish && !isFinalChoicePending
    }

    func startNewGame() {
        gameState = GameState()
        collectedPartIDs = []
        buildWorld()
    }

    func loadGame(_ savedState: GameState) {
        gameState = savedState
        collectedPartIDs = savedState.collectedPartIDs
        buildWorld()
    }

    func flushProgress() {
        guard hasBuiltWorld, gameState.hasStarted else { return }
        updateStoredRunState()
        onProgress?(gameState)
    }

    func setHapticsEnabled(_ enabled: Bool) {
        heartbeat.isEnabled = enabled
    }

    func escapeEarly() {
        guard hasBuiltWorld, !didFinish, !isFinalChoicePending,
              collectedPartIDs.count < 5, let player,
              pointDistance(player.position, exitPosition) <= 45 * scaleFactor else { return }
        gameState.escapedEarly = true
        finish(with: .earlyEscape)
    }

    func chooseStationTruth() {
        guard isFinalChoicePending, !didFinish else { return }
        finish(with: .stationTruth)
    }

    func chooseSacrificeLight() {
        guard isFinalChoicePending, !didFinish else { return }
        flashlight.sacrifice()
        gameState.sacrificedLight = true
        finish(with: .tragic)
    }

    func waitInHidingUntilSignalFades() {
        guard isHiding, !didFinish else { return }
        isWaitingInHiding = true
        publishSnapshot(forceSave: true)
    }

    func toggleHiding() {
        guard hasBuiltWorld, !didFinish, !isFinalChoicePending, let player else { return }
        if isHiding {
            isHiding = false
            holdingBreath = false
            isWaitingInHiding = false
            hideWaitRemaining = 30
            breathNoiseClock = 0
            activeLockerPosition = nil
            player.isHidden = false
            player.physicsBody?.velocity = .zero
            publishSnapshot(forceSave: true)
            return
        }
        guard let locker = lockerPositions.min(by: { pointDistance($0, player.position) < pointDistance($1, player.position) }),
              pointDistance(locker, player.position) <= 39 * scaleFactor else { return }
        isHiding = true
        holdingBreath = false
        activeLockerPosition = locker
        player.position = locker
        player.movementInput = .zero
        player.physicsBody?.velocity = .zero
        player.isHidden = true
        publishSnapshot(forceSave: true)
    }

    func setHoldingBreath(_ isHolding: Bool) {
        holdingBreath = isHolding && isHiding && !didFinish
        if !holdingBreath { breathNoiseClock = 0 }
        publishSnapshot()
    }

    func rescueSurvivor() {
        guard hasBuiltWorld, !didFinish, !isFinalChoicePending, !survivorFollowing, let player, let survivor,
              pointDistance(survivor.position, player.position) <= 37 * scaleFactor else { return }
        survivorFollowing = true
        survivor.beginFollowing()
        publishSnapshot(forceSave: true)
    }

    func toggleFlashlight() {
        guard !didFinish, !isFinalChoicePending else { return }
        flashlight.toggle()
        publishSnapshot()
    }

    func cycleFlashlightLevel() {
        guard !didFinish, !isFinalChoicePending else { return }
        flashlight.cycleLevel()
        publishSnapshot()
    }

    func placeFlare() {
        guard hasBuiltWorld, !didFinish, !isFinalChoicePending, let player else { return }
        flare?.removeFromParent()
        let newFlare = LitFlare(scaleFactor: scaleFactor)
        newFlare.position = CGPoint(
            x: player.position.x + player.facingDirection.dx * 46 * scaleFactor,
            y: player.position.y + player.facingDirection.dy * 46 * scaleFactor
        )
        flare = newFlare
        addChild(newFlare)
        AudioManager.play(.flareIgnition, at: newFlare.position)
        publishSnapshot()
    }

    /// Throws a noisy object toward the nearest nearby sealed door; if no door is
    /// in range, it lands ahead of the player and still attracts the sound hunter.
    func throwNoiseItem() {
        guard hasBuiltWorld, !didFinish, !isFinalChoicePending, throwItemsRemaining > 0, let player else { return }
        throwItemsRemaining -= 1
        publishSnapshot()
        let nearestDoor = sealedDoors
            .filter { !$0.isOpen }
            .min { pointDistance($0.center, player.position) < pointDistance($1.center, player.position) }
        let canReachDoor = nearestDoor.map { pointDistance($0.center, player.position) <= 250 * scaleFactor } ?? false
        let impact = canReachDoor ? nearestDoor!.center : CGPoint(
            x: player.position.x + player.facingDirection.dx * 112 * scaleFactor,
            y: player.position.y + player.facingDirection.dy * 112 * scaleFactor
        )

        let projectile = SKShapeNode(circleOfRadius: 4 * scaleFactor)
        projectile.fillColor = UIColor(red: 0.80, green: 0.87, blue: 0.89, alpha: 1)
        projectile.strokeColor = UIColor(white: 1, alpha: 0.8)
        projectile.glowWidth = 4 * scaleFactor
        projectile.position = player.position
        projectile.zPosition = 16
        addChild(projectile)
        let travel = SKAction.move(to: impact, duration: 0.34)
        travel.timingMode = .easeOut
        projectile.run(.sequence([travel, .wait(forDuration: 0.06), .removeFromParent()])) { [weak self] in
            guard let self else { return }
            self.noiseSystem.emit(
                source: .thrownItem,
                at: impact,
                baseRadius: 390 * self.scaleFactor,
                surface: .metal,
                time: self.sceneClock
            )
            AudioManager.play(.doorRattle, at: impact)
        }
    }

    func restart() {
        startNewGame()
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
        guard hasBuiltWorld, let player, let deathAngel, let demogorgon else { return }
        guard !didFinish else { return }

        if isHiding || didFinish || isFinalChoicePending { player.movementInput = .zero }
        player.updateMovement(
            delta: delta,
            surface: surface(at: player.position),
            noiseSystem: noiseSystem,
            sceneTime: currentTime,
            speedMultiplier: survivorFollowing ? 0.78 : 1
        )
        flashlight.update(delta: delta)
        deathAngel.isInDeadlyCorridor = narrowCorridorRect.contains(player.position) && narrowCorridorRect.contains(deathAngel.position)
        demogorgon.isInWeakCorridor = narrowCorridorRect.contains(player.position) && narrowCorridorRect.contains(demogorgon.position)

        if let flare, flare.advance(delta: delta) {
            flare.removeFromParent()
            self.flare = nil
        }
        demogorgon.observe(
            playerPosition: player.position,
            flashlightOn: flashlight.isOn,
            level: flashlight.level,
            flarePosition: flare?.position,
            time: delta,
            playerHidden: isHiding
        )

        deathAngel.advance(delta: delta)
        demogorgon.advance(delta: delta)
        monsterDirector.advance(delta: delta)
        if isWaitingInHiding && isHiding {
            hideWaitRemaining = max(0, hideWaitRemaining - delta)
            if hideWaitRemaining <= 0 {
                gameState.hidUntilEnd = true
                finish(with: .ambiguous)
                return
            }
        }
        if checkForMonsterCapture() { return }
        updateCollectiblePickups()
        if didFinish { return }
        updateSurvivorFollower(delta: delta)
        updateBreathPressure(delta: delta)
        checkGlass(at: player.position, time: currentTime)
        updatePlayerHabit(delta: delta)

        AudioManager.setListenerPosition(player.position)
        fogClock += delta
        if fogClock >= 0.08 {
            fogClock = 0
            updateFogOfWar()
        }
        updateThreatFeedback(delta: delta)

        publishClock += delta
        if publishClock >= 0.16 {
            publishClock = 0
            publishSnapshot()
        }
        progressSaveClock += delta
        if progressSaveClock >= 1 {
            progressSaveClock = 0
            flushProgress()
        }
    }

    private func buildWorld() {
        hasBuiltWorld = false
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
        pitchDarkRoomRect = CGRect(
            x: roomBounds.minX + roomBounds.width * 0.055,
            y: roomBounds.minY + roomBounds.height * 0.715,
            width: roomBounds.width * 0.31,
            height: roomBounds.height * 0.22
        )
        narrowCorridorRect = CGRect(
            x: roomBounds.minX + roomBounds.width * 0.435,
            y: roomBounds.minY + roomBounds.height * 0.045,
            width: roomBounds.width * 0.17,
            height: roomBounds.height * 0.91
        )

        glassBroken = false
        lastUpdateTime = 0
        publishClock = 0
        fogClock = 0
        sceneClock = 0
        habitClock = 0
        progressSaveClock = 0
        isHiding = gameState.hasStarted && gameState.isHiding
        holdingBreath = false
        breathMeter = 0
        breathNoiseClock = 0
        lockerPositions = []
        activeLockerPosition = nil
        collectibleParts = []
        collectedPartIDs = gameState.hasStarted ? gameState.collectedPartIDs : []
        points = gameState.hasStarted ? gameState.points : 0
        throwItemsRemaining = gameState.hasStarted ? gameState.throwItemsRemaining : 3
        survivorFollowing = gameState.hasStarted && gameState.savedSurvivor
        didFinish = false
        didLose = false
        isFinalChoicePending = gameState.hasStarted && gameState.isFinalChoicePending
        isWaitingInHiding = gameState.hasStarted && gameState.isWaitingInHiding
        hideWaitRemaining = gameState.hasStarted ? gameState.hideWaitRemaining : 30
        flashlight = FlashlightSystem()
        if gameState.hasStarted,
           let savedLevel = FlashlightLevel(rawValue: gameState.flashlightLevel) {
            flashlight.restore(
                batteryPercent: CGFloat(gameState.batteryPercent),
                level: savedLevel,
                isOn: gameState.flashlightOn
            )
        }
        monsterMemory = MonsterMemory()
        monsterDirector = MonsterDirector()
        flare = nil
        sealedDoors = []
        fogTiles = []
        noiseSystem = NoiseSystem()

        drawRoom()
        addRoomWalls()
        addLevelFeatures()
        addSurfaceZone(carpetRect, title: "سجاد · هادئ", color: UIColor(red: 0.20, green: 0.31, blue: 0.33, alpha: 0.55))
        addSurfaceZone(glassRect, title: "زجاج · خطر", color: UIColor(red: 0.28, green: 0.46, blue: 0.53, alpha: 0.46))

        let start = CGPoint(x: roomBounds.midX, y: roomBounds.minY + roomBounds.height * 0.12)
        player = Player(scaleFactor: scaleFactor)
        let restoredPosition = CGPoint(
            x: roomBounds.minX + roomBounds.width * CGFloat(gameState.playerXRatio),
            y: roomBounds.minY + roomBounds.height * CGFloat(gameState.playerYRatio)
        )
        player.position = gameState.hasStarted ? restoredPosition : start
        player.isHidden = isHiding
        if isHiding { activeLockerPosition = player.position }
        addChild(player)
        exitPosition = CGPoint(x: roomBounds.midX, y: roomBounds.minY + roomBounds.height * 0.06)
        addEmergencyExit(at: exitPosition)

        let lockers = [
            CGPoint(x: roomBounds.minX + roomBounds.width * 0.17, y: roomBounds.minY + roomBounds.height * 0.56),
            CGPoint(x: roomBounds.maxX - roomBounds.width * 0.15, y: roomBounds.minY + roomBounds.height * 0.48),
            CGPoint(x: roomBounds.minX + roomBounds.width * 0.78, y: roomBounds.maxY - roomBounds.height * 0.13)
        ]
        lockerPositions = lockers
        lockers.forEach { addLocker(at: $0) }

        let patrolPoints = [
            CGPoint(x: roomBounds.minX + roomBounds.width * 0.24, y: roomBounds.maxY - roomBounds.height * 0.13),
            CGPoint(x: roomBounds.maxX - roomBounds.width * 0.23, y: roomBounds.maxY - roomBounds.height * 0.16),
            CGPoint(x: roomBounds.maxX - roomBounds.width * 0.20, y: roomBounds.minY + roomBounds.height * 0.60),
            CGPoint(x: roomBounds.minX + roomBounds.width * 0.20, y: roomBounds.minY + roomBounds.height * 0.60)
        ]
        let darkRoomPatrol = [
            CGPoint(x: pitchDarkRoomRect.midX, y: pitchDarkRoomRect.midY),
            CGPoint(x: pitchDarkRoomRect.maxX - 12 * scaleFactor, y: pitchDarkRoomRect.midY),
            CGPoint(x: pitchDarkRoomRect.midX, y: pitchDarkRoomRect.minY + 10 * scaleFactor)
        ]
        let habitZones: [(String, CGPoint)] = [
            ("north", CGPoint(x: roomBounds.midX, y: roomBounds.maxY - roomBounds.height * 0.16)),
            ("south", CGPoint(x: roomBounds.midX, y: roomBounds.minY + roomBounds.height * 0.17)),
            ("west", CGPoint(x: roomBounds.minX + roomBounds.width * 0.20, y: roomBounds.midY)),
            ("east", CGPoint(x: roomBounds.maxX - roomBounds.width * 0.20, y: roomBounds.midY)),
            ("dark", pitchDarkRoomRect.midPoint)
        ]
        habitZones.forEach { monsterMemory.registerZone($0.0, center: $0.1) }
        spawnCollectibleParts(patrolRoutes: [patrolPoints, darkRoomPatrol])
        survivor = SurvivorNPC(scaleFactor: scaleFactor)
        survivor.position = CGPoint(x: roomBounds.minX + roomBounds.width * 0.78, y: roomBounds.minY + roomBounds.height * 0.19)
        if survivorFollowing { survivor.beginFollowing() }
        addChild(survivor)

        deathAngel = DeathAngelAI(scaleFactor: scaleFactor, patrolPoints: patrolPoints, hidingSpots: lockers, memory: monsterMemory)
        deathAngel.position = CGPoint(x: roomBounds.midX, y: roomBounds.maxY - roomBounds.height * 0.12)
        deathAngel.onStateChange = { [weak self] _ in self?.publishSnapshot() }
        addChild(deathAngel)

        demogorgon = DemogorgonAI(scaleFactor: scaleFactor, patrolPoints: darkRoomPatrol + patrolPoints, hidingSpots: lockers, memory: monsterMemory)
        demogorgon.position = CGPoint(x: pitchDarkRoomRect.midX, y: pitchDarkRoomRect.midY)
        demogorgon.onStateChange = { [weak self] _ in self?.publishSnapshot() }
        addChild(demogorgon)

        noiseSystem.onNoise = { [weak self] event in
            guard let self else { return }
            self.deathAngel.hear(event)
            let openedDoor = self.openDoorIfHit(by: event)
            if openedDoor {
                self.monsterDirector.wakeDeathAngel()
            } else if event.source == .runningFootstep || event.source == .glassBreak || event.radius >= 255 * self.scaleFactor {
                self.monsterDirector.notifyLoudNoise()
            }
            self.publishSnapshot()
        }

        configureMonsterDirector()
        createFogTiles()
        configureCameraFeedback()
        hasBuiltWorld = true
        gameState.hasStarted = true
        updateFogOfWar()
        AudioManager.setListenerPosition(player.position)
        AudioManager.play(.distantFootsteps, at: offscreenAudioPoint())
        publishSnapshot()
        flushProgress()
    }

    private func drawRoom() {
        let floor = SKShapeNode(rect: roomBounds, cornerRadius: 18 * scaleFactor)
        floor.fillColor = UIColor(red: 0.025, green: 0.046, blue: 0.055, alpha: 1)
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
        edge.physicsBody?.collisionBitMask = PhysicsCategory.player | PhysicsCategory.hunter | PhysicsCategory.companion
        edge.zPosition = 2
        addChild(edge)
        addLabel("ممرّ المحطة 09", at: CGPoint(x: roomBounds.midX, y: roomBounds.maxY - 24 * scaleFactor), size: 10 * scaleFactor, color: UIColor(white: 0.77, alpha: 0.70))
    }

    private func addRoomWalls() {
        let wallThickness = 8 * scaleFactor
        let upperY = roomBounds.minY + roomBounds.height * 0.67
        let lowerY = roomBounds.minY + roomBounds.height * 0.34
        let gapWidth = roomBounds.width * 0.27
        addWall(rect: CGRect(x: roomBounds.minX + 1, y: upperY, width: (roomBounds.width - gapWidth) / 2, height: wallThickness))
        addWall(rect: CGRect(x: roomBounds.midX + gapWidth / 2, y: upperY, width: (roomBounds.width - gapWidth) / 2 - 1, height: wallThickness))
        addWall(rect: CGRect(x: roomBounds.minX + 1, y: lowerY, width: (roomBounds.width - gapWidth) / 2, height: wallThickness))
        addWall(rect: CGRect(x: roomBounds.midX + gapWidth / 2, y: lowerY, width: (roomBounds.width - gapWidth) / 2 - 1, height: wallThickness))

        let upperDoor = CGRect(x: roomBounds.midX - gapWidth / 2, y: upperY, width: gapWidth, height: wallThickness)
        let lowerDoor = CGRect(x: roomBounds.midX - gapWidth / 2, y: lowerY, width: gapWidth, height: wallThickness)
        sealedDoors = [SealedDoor(rect: upperDoor, scaleFactor: scaleFactor, label: "باب مختوم ١"), SealedDoor(rect: lowerDoor, scaleFactor: scaleFactor, label: "باب مختوم ٢")]
        sealedDoors.forEach { addChild($0.node) }

        let dividerWidth = 7 * scaleFactor
        addWall(rect: CGRect(x: roomBounds.minX + roomBounds.width * 0.34, y: roomBounds.minY + roomBounds.height * 0.12, width: dividerWidth, height: roomBounds.height * 0.20))
    }

    private func addEmergencyExit(at point: CGPoint) {
        let door = SKShapeNode(rectOf: CGSize(width: 30 * scaleFactor, height: 11 * scaleFactor), cornerRadius: 3 * scaleFactor)
        door.name = "emergencyExit"
        door.position = point
        door.fillColor = UIColor(red: 0.06, green: 0.37, blue: 0.31, alpha: 0.96)
        door.strokeColor = UIColor(red: 0.38, green: 0.97, blue: 0.74, alpha: 0.95)
        door.lineWidth = 1.5 * scaleFactor
        door.glowWidth = 7 * scaleFactor
        door.zPosition = 31
        addChild(door)
        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = "مخرج الطوارئ"
        label.fontSize = 6.5 * scaleFactor
        label.fontColor = UIColor(red: 0.64, green: 1, blue: 0.83, alpha: 0.95)
        label.position = CGPoint(x: point.x, y: point.y - 14 * scaleFactor)
        label.zPosition = 32
        addChild(label)
    }

    private func addLevelFeatures() {
        let darkRoom = SKShapeNode(rect: pitchDarkRoomRect, cornerRadius: 8 * scaleFactor)
        darkRoom.fillColor = UIColor(red: 0.003, green: 0.006, blue: 0.009, alpha: 1)
        darkRoom.strokeColor = UIColor(red: 0.24, green: 0.31, blue: 0.34, alpha: 0.42)
        darkRoom.lineWidth = 1 * scaleFactor
        darkRoom.zPosition = 2
        addChild(darkRoom)
        addLabel("غرفة مظلمة · الضوء ضروري", at: CGPoint(x: pitchDarkRoomRect.midX, y: pitchDarkRoomRect.midY), size: 7.5 * scaleFactor, color: UIColor(white: 0.82, alpha: 0.70))

        let corridor = SKShapeNode(rect: narrowCorridorRect, cornerRadius: 8 * scaleFactor)
        corridor.fillColor = UIColor(red: 0.17, green: 0.11, blue: 0.09, alpha: 0.22)
        corridor.strokeColor = UIColor(red: 0.76, green: 0.36, blue: 0.22, alpha: 0.48)
        corridor.lineWidth = 1.4 * scaleFactor
        corridor.zPosition = 3
        addChild(corridor)

        // Side walls turn the marked route into a genuinely narrow passage;
        // its ends remain open beyond the two noise-locked cross doors.
        let wallThickness = 5 * scaleFactor
        let lowerY = roomBounds.minY + roomBounds.height * 0.34 + 8 * scaleFactor
        let upperY = roomBounds.minY + roomBounds.height * 0.67 - 8 * scaleFactor
        let corridorWallHeight = max(0, upperY - lowerY)
        addWall(rect: CGRect(x: narrowCorridorRect.minX - wallThickness, y: lowerY, width: wallThickness, height: corridorWallHeight))
        addWall(rect: CGRect(x: narrowCorridorRect.maxX, y: lowerY, width: wallThickness, height: corridorWallHeight))
        addLabel("ممرّ ضيّق · Death Angel أسرع", at: CGPoint(x: narrowCorridorRect.midX, y: narrowCorridorRect.midY), size: 6.8 * scaleFactor, color: UIColor(red: 1, green: 0.65, blue: 0.45, alpha: 0.84))
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
        wall.physicsBody?.collisionBitMask = PhysicsCategory.player | PhysicsCategory.hunter | PhysicsCategory.companion
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

    private func addLocker(at point: CGPoint) {
        let rect = CGRect(x: point.x - 11 * scaleFactor, y: point.y - 15 * scaleFactor, width: 22 * scaleFactor, height: 30 * scaleFactor)
        let locker = SKShapeNode(rect: rect, cornerRadius: 3 * scaleFactor)
        locker.fillColor = UIColor(red: 0.12, green: 0.17, blue: 0.19, alpha: 0.94)
        locker.strokeColor = UIColor(red: 0.49, green: 0.61, blue: 0.63, alpha: 0.72)
        locker.lineWidth = 1 * scaleFactor
        locker.zPosition = 5
        addChild(locker)
        let seam = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: point.x, y: rect.minY + 2 * scaleFactor))
        path.addLine(to: CGPoint(x: point.x, y: rect.maxY - 2 * scaleFactor))
        seam.path = path
        seam.strokeColor = UIColor(white: 0.72, alpha: 0.44)
        seam.lineWidth = 0.7 * scaleFactor
        seam.zPosition = 6
        addChild(seam)
        addLabel("خزانة", at: CGPoint(x: point.x, y: rect.minY - 7 * scaleFactor), size: 6 * scaleFactor, color: UIColor(white: 0.80, alpha: 0.67))
    }

    private func spawnCollectibleParts(patrolRoutes: [[CGPoint]]) {
        let placements: [(x: CGFloat, y: CGFloat, noisy: Bool)] = [
            (0.18, 0.49, false),
            (0.80, 0.55, true),
            (0.20, 0.83, false),
            (0.80, 0.82, true),
            (0.73, 0.24, false)
        ]
        for (offset, placement) in placements.enumerated() {
            let partID = offset + 1
            guard !collectedPartIDs.contains(partID) else { continue }
            let point = CGPoint(
                x: roomBounds.minX + roomBounds.width * placement.x,
                y: roomBounds.minY + roomBounds.height * placement.y
            )
            let routeDistance = patrolRoutes.flatMap { route in
                route.indices.map { index in
                    distance(point, toSegmentFrom: route[index], to: route[(index + 1) % route.count])
                }
            }.min() ?? .greatestFiniteMagnitude
            let value = routeDistance <= 72 * scaleFactor ? 3 : (routeDistance <= 148 * scaleFactor ? 2 : 1)
            let part = CollectiblePart(index: partID, pointValue: value, isNoisy: placement.noisy, scaleFactor: scaleFactor)
            part.position = point
            collectibleParts.append(part)
            addChild(part)
        }
    }

    private func distance(_ point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return pointDistance(point, start) }
        let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let t = min(max(projection, 0), 1)
        let closest = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return pointDistance(point, closest)
    }

    private func updateCollectiblePickups() {
        guard !didFinish, !isFinalChoicePending else { return }
        let collected = collectibleParts.filter { pointDistance(player.position, $0.position) <= 18 * scaleFactor }
        guard !collected.isEmpty else { return }
        for part in collected {
            collectedPartIDs.insert(part.index)
            points += part.pointValue
            if part.isNoisy {
                noiseSystem.emit(
                    source: .loudPickup,
                    at: part.position,
                    baseRadius: 210 * scaleFactor,
                    surface: surface(at: part.position),
                    time: sceneClock
                )
                AudioManager.play(.doorRattle, at: part.position)
            }
            part.removeFromParent()
            collectibleParts.removeAll { $0 === part }
        }
        if collectedPartIDs.count >= 5 {
            player.movementInput = .zero
            player.sprintRequested = false
            player.physicsBody?.velocity = .zero
            if survivorFollowing {
                finish(with: .tragic)
                return
            }
            isFinalChoicePending = true
        }
        publishSnapshot(forceSave: true)
    }

    private func updateSurvivorFollower(delta: TimeInterval) {
        guard survivorFollowing, let survivor else { return }
        if survivor.advance(delta: delta, following: player.position) {
            noiseSystem.emit(
                source: .survivorFootstep,
                at: survivor.position,
                baseRadius: 132 * scaleFactor,
                surface: surface(at: survivor.position),
                time: sceneClock
            )
            AudioManager.play(.playerFootstep, at: survivor.position)
        }
    }

    private func updateBreathPressure(delta: TimeInterval) {
        guard isHiding else {
            breathMeter = max(0, breathMeter - CGFloat(delta) * 0.7)
            breathNoiseClock = 0
            return
        }
        let monsterNearby = (deathAngel.isActive && pointDistance(player.position, deathAngel.position) <= 205 * scaleFactor)
            || (demogorgon.isActive && pointDistance(player.position, demogorgon.position) <= 205 * scaleFactor)
        guard monsterNearby else {
            breathMeter = max(0, breathMeter - CGFloat(delta) * 0.58)
            breathNoiseClock = 0
            return
        }

        let rate: CGFloat = holdingBreath ? 0.18 : 0.38
        breathMeter = min(1, breathMeter + CGFloat(max(0, delta)) * rate)
        if holdingBreath {
            breathNoiseClock = 0
            if breathMeter >= 1 {
                holdingBreath = false
                breathMeter = 0.62
                emitBreathNoise()
            }
        } else {
            breathNoiseClock += max(0, delta)
            if breathNoiseClock >= 1.15 {
                breathNoiseClock = 0
                emitBreathNoise()
            }
        }
    }

    private func emitBreathNoise() {
        let origin = activeLockerPosition ?? player.position
        noiseSystem.emit(
            source: .breathing,
            at: origin,
            baseRadius: 155 * scaleFactor,
            surface: .metal,
            time: sceneClock
        )
    }

    private func canEnterNearbyLocker() -> Bool {
        guard !isHiding else { return true }
        guard let player else { return false }
        return lockerPositions.contains { pointDistance($0, player.position) <= 39 * scaleFactor }
    }

    private func canReachSurvivor() -> Bool {
        guard !survivorFollowing, let player, let survivor else { return false }
        return pointDistance(survivor.position, player.position) <= 37 * scaleFactor
    }

    private func addLabel(_ text: String, at position: CGPoint, size: CGFloat, color: UIColor) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Medium")
        label.text = text
        label.fontSize = size
        label.fontColor = color
        label.position = position
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 7
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
        AudioManager.play(.glassBreak, at: point)
    }

    private func openDoorIfHit(by event: NoiseEvent) -> Bool {
        guard event.source == .thrownItem || event.source == .glassBreak else { return false }
        guard let door = sealedDoors.first(where: { !$0.isOpen && pointDistance($0.center, event.position) <= 52 * scaleFactor }) else { return false }
        door.open()
        return true
    }

    private func configureMonsterDirector() {
        monsterDirector.onBuildUpSound = { [weak self] secondCue in
            guard let self else { return }
            let source = self.offscreenAudioPoint()
            AudioManager.play(secondCue ? .doorRattle : .distantFootsteps, at: source)
        }
        monsterDirector.onAttack = { [weak self] kind in
            guard let self else { return }
            self.deathAngel.setActive(false)
            self.demogorgon.setActive(false)
            if kind == .deathAngel {
                self.deathAngel.position = CGPoint(x: self.roomBounds.minX + self.roomBounds.width * 0.17, y: self.roomBounds.maxY - self.roomBounds.height * 0.18)
                self.deathAngel.setActive(true)
            } else {
                self.demogorgon.position = CGPoint(x: self.pitchDarkRoomRect.midX, y: self.pitchDarkRoomRect.midY)
                self.demogorgon.setActive(true)
            }
            self.publishSnapshot()
        }
        monsterDirector.onRetreat = { [weak self] in
            self?.deathAngel.setActive(false)
            self?.demogorgon.setActive(false)
            self?.publishSnapshot()
        }
        monsterDirector.onPhaseChange = { [weak self] phase in
            guard let self else { return }
            self.publishSnapshot()
            if phase == .calm {
                AudioManager.play(.distantFootsteps, at: self.offscreenAudioPoint())
            }
        }
    }

    private func offscreenAudioPoint() -> CGPoint {
        let candidates = [
            CGPoint(x: roomBounds.minX + 18 * scaleFactor, y: roomBounds.midY),
            CGPoint(x: roomBounds.maxX - 18 * scaleFactor, y: roomBounds.midY),
            CGPoint(x: roomBounds.midX, y: roomBounds.maxY - 18 * scaleFactor),
            CGPoint(x: roomBounds.midX, y: roomBounds.minY + 18 * scaleFactor)
        ]
        return candidates.max { pointDistance($0, player.position) < pointDistance($1, player.position) } ?? roomBounds.center
    }

    private func updatePlayerHabit(delta: TimeInterval) {
        habitClock += delta
        guard habitClock >= 1.2 else { return }
        habitClock = 0
        guard player.speedMode == .run || flashlight.isOn else { return }
        let zoneID = zoneID(at: player.position)
        monsterMemory.recordUse(in: zoneID)
    }

    private func zoneID(at point: CGPoint) -> String {
        if pitchDarkRoomRect.contains(point) { return "dark" }
        let dx = point.x - roomBounds.midX
        let dy = point.y - roomBounds.midY
        if abs(dy) > abs(dx) { return dy >= 0 ? "north" : "south" }
        return dx >= 0 ? "east" : "west"
    }

    private func createFogTiles() {
        fogTiles = []
        let columns = 16
        let rows = 24
        let tileWidth = roomBounds.width / CGFloat(columns)
        let tileHeight = roomBounds.height / CGFloat(rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let rect = CGRect(
                    x: roomBounds.minX + CGFloat(column) * tileWidth,
                    y: roomBounds.minY + CGFloat(row) * tileHeight,
                    width: tileWidth + 0.6,
                    height: tileHeight + 0.6
                )
                let node = SKShapeNode(rect: rect)
                node.fillColor = UIColor.black
                node.strokeColor = .clear
                node.alpha = 0.97
                node.zPosition = 30
                addChild(node)
                fogTiles.append(FogTile(rect: rect, node: node))
            }
        }
    }

    private func updateFogOfWar() {
        guard let player else { return }
        let facingAngle = atan2(player.facingDirection.dy, player.facingDirection.dx)
        for tile in fogTiles {
            let point = tile.rect.midPoint
            let dx = point.x - player.position.x
            let dy = point.y - player.position.y
            let distance = hypot(dx, dy)
            let angle = atan2(dy, dx)
            let angleDifference = abs(atan2(sin(angle - facingAngle), cos(angle - facingAngle)))
            let visible = flashlight.isOn && (distance <= 24 * scaleFactor || (distance <= flashlight.level.revealRange * scaleFactor && angleDifference <= 0.62))
            if visible { tile.isExplored = true }
            let targetAlpha: CGFloat = visible ? 0.035 : (tile.isExplored ? 0.68 : 0.97)
            tile.node.alpha = targetAlpha
        }
    }

    private func configureCameraFeedback() {
        cameraNode = SKCameraNode()
        cameraNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(cameraNode)
        camera = cameraNode
        vignetteNode = SKShapeNode(rectOf: size, cornerRadius: 24 * scaleFactor)
        vignetteNode.position = .zero
        vignetteNode.fillColor = UIColor(red: 0.48, green: 0.035, blue: 0.025, alpha: 0)
        vignetteNode.strokeColor = UIColor(red: 0.88, green: 0.08, blue: 0.035, alpha: 0)
        vignetteNode.lineWidth = 26 * scaleFactor
        vignetteNode.glowWidth = 15 * scaleFactor
        vignetteNode.zPosition = 100
        cameraNode.addChild(vignetteNode)
    }

    private func updateThreatFeedback(delta: TimeInterval) {
        guard let player, let cameraNode, let vignetteNode else { return }
        var threat: CGFloat = 0
        if deathAngel.isActive {
            threat = max(threat, max(0, 1 - pointDistance(player.position, deathAngel.position) / (300 * scaleFactor)))
        }
        if demogorgon.isActive {
            threat = max(threat, max(0, 1 - pointDistance(player.position, demogorgon.position) / (300 * scaleFactor)))
        }
        heartbeat.update(threat: threat, delta: delta)
        let pulse = 0.5 + 0.5 * CGFloat(sin(sceneClock * 7.5))
        vignetteNode.fillColor = UIColor(red: 0.48, green: 0.035, blue: 0.025, alpha: threat * 0.075 * pulse)
        vignetteNode.strokeColor = UIColor(red: 0.88, green: 0.08, blue: 0.035, alpha: threat * (0.10 + 0.22 * pulse))
        let shake = threat * 5 * scaleFactor
        cameraNode.position = CGPoint(
            x: size.width / 2 + sin(sceneClock * 31) * shake,
            y: size.height / 2 + cos(sceneClock * 27) * shake
        )
    }

    private func publishSnapshot(forceSave: Bool = false) {
        guard hasBuiltWorld, let player, let deathAngel, let demogorgon else { return }
        let activeNoise = noiseSystem.latestEvent.flatMap { sceneClock - $0.timestamp < 3.0 ? $0 : nil }
        let intensity = min((activeNoise?.radius ?? 0) / (420 * scaleFactor), 1)
        let message: String

        if didFinish {
            message = didLose ? "أمسك بك أحد الصيادين. حاول من جديد، وراقب الضوء والصوت." : (gameState.ending?.message ?? "انتهت الجولة.")
        } else if isFinalChoicePending {
            message = "اكتملت الأجزاء. اختر: أرسل الإشارة أو أضحِّ بالضوء."
        } else if isWaitingInHiding {
            message = "ابقَ في الخزانة حتى تنقطع الإشارة: \(Int(ceil(hideWaitRemaining)))ث."
        } else if isHiding {
            message = holdingBreath ? "أنت داخل الخزانة. احبس نفسك ما دام عدّاد النفس يسمح." : "الخزانة تخفيك عن نظر Demogorgon؛ Death Angel ما زال يسمعك."
        } else if survivorFollowing {
            message = "الناجي يتبعك ويبطئك؛ خطواته قد تجذب Death Angel."
        } else if monsterDirector.phase == .calm {
            message = flashlight.isOn ? "هدوء مؤقت… الضوء قد يجذب Demogorgon." : "هدوء مؤقت. في الظلام لا يراك Demogorgon إلا عن قرب."
        } else if monsterDirector.phase == .buildUp {
            message = "أصوات بعيدة… سيصمت المكان قبل دخول الوحش."
        } else if monsterDirector.phase == .retreat {
            message = "انسحب الوحش. استغل الهدوء وراقب البطارية."
        } else if monsterDirector.activeMonster == .demogorgon {
            message = demogorgon.state == .search ? "يفتش آخر موضع رآك فيه ثم الخزائن القريبة." : "Demogorgon يلاحق الضوء؛ أطفئ المصباح وغيّر موقعك."
        } else {
            switch deathAngel.state {
            case .patrol: message = "Death Angel في دوريته. تحرّك بهدوء."
            case .investigate: message = "سمع Death Angel ضوضاء ويتجه إلى مصدرها."
            case .chase: message = "الصوت العالي أيقظ Death Angel؛ غيّر موقعك."
            case .search: message = "يفتش حول آخر صوت ثم الخزائن القريبة."
            }
        }

        updateStoredRunState()
        onSnapshot?(GameSnapshot(
            playerSpeed: player.speedMode,
            deathAngelState: deathAngel.state,
            demogorgonState: demogorgon.state,
            surface: surface(at: player.position),
            noiseIntensity: intensity,
            flashlightLevel: flashlight.level,
            flashlightOn: flashlight.isOn,
            batteryPercent: flashlight.batteryPercent,
            pressurePhase: monsterDirector.phase,
            activeMonster: monsterDirector.activeMonster,
            threatIntensity: threatLevel(),
            flareSecondsRemaining: flare?.remainingTime ?? 0,
            statusMessage: message,
            collectedParts: collectedPartIDs.count,
            totalParts: 5,
            points: points,
            throwItemsRemaining: throwItemsRemaining,
            isHiding: isHiding,
            breathMeter: breathMeter,
            isHoldingBreath: holdingBreath,
            canHide: canEnterNearbyLocker(),
            canRescueSurvivor: canReachSurvivor(),
            survivorFollowing: survivorFollowing,
            isFinalChoicePending: isFinalChoicePending,
            canEscapeEarly: !didFinish && !isFinalChoicePending && collectedPartIDs.count < 5
                && pointDistance(player.position, exitPosition) <= 45 * scaleFactor,
            isWaitingInHiding: isWaitingInHiding,
            hideWaitRemaining: hideWaitRemaining,
            didFinish: didFinish,
            didLose: didLose,
            ending: gameState.ending
        ))
        if forceSave { onProgress?(gameState) }
    }

    private func updateStoredRunState() {
        guard let player, roomBounds.width > 0, roomBounds.height > 0 else { return }
        gameState.hasStarted = true
        gameState.collectedPartIDs = collectedPartIDs
        gameState.points = points
        gameState.throwItemsRemaining = throwItemsRemaining
        gameState.playerXRatio = Double(min(max((player.position.x - roomBounds.minX) / roomBounds.width, 0), 1))
        gameState.playerYRatio = Double(min(max((player.position.y - roomBounds.minY) / roomBounds.height, 0), 1))
        gameState.batteryPercent = Double(flashlight.batteryPercent)
        gameState.flashlightOn = flashlight.isOn
        gameState.flashlightLevel = flashlight.level.rawValue
        gameState.savedSurvivor = survivorFollowing
        gameState.isHiding = isHiding
        gameState.isWaitingInHiding = isWaitingInHiding
        gameState.hideWaitRemaining = hideWaitRemaining
        gameState.isFinalChoicePending = isFinalChoicePending
        gameState.didDie = didLose
    }

    private func finish(with ending: GameEnding) {
        guard !didFinish else { return }
        didFinish = true
        isFinalChoicePending = false
        isWaitingInHiding = false
        player?.movementInput = .zero
        player?.sprintRequested = false
        player?.physicsBody?.velocity = .zero
        gameState.ending = ending
        gameState.didDie = false
        if ending == .earlyEscape { gameState.escapedEarly = true }
        if ending == .ambiguous { gameState.hidUntilEnd = true }
        publishSnapshot(forceSave: true)
    }

    private func checkForMonsterCapture() -> Bool {
        guard !didFinish, !isHiding, let player else { return false }
        let caughtByDeathAngel = deathAngel.isActive && pointDistance(player.position, deathAngel.position) <= 26 * scaleFactor
        let caughtByDemogorgon = demogorgon.isActive && pointDistance(player.position, demogorgon.position) <= 28 * scaleFactor
        guard caughtByDeathAngel || caughtByDemogorgon else { return false }
        didFinish = true
        didLose = true
        player.movementInput = .zero
        player.sprintRequested = false
        player.physicsBody?.velocity = .zero
        gameState.ending = nil
        gameState.didDie = true
        publishSnapshot(forceSave: true)
        return true
    }

    private func threatLevel() -> CGFloat {
        guard let player else { return 0 }
        var threat: CGFloat = 0
        if deathAngel.isActive { threat = max(threat, max(0, 1 - pointDistance(player.position, deathAngel.position) / (300 * scaleFactor))) }
        if demogorgon.isActive { threat = max(threat, max(0, 1 - pointDistance(player.position, demogorgon.position) / (300 * scaleFactor))) }
        return min(max(threat, 0), 1)
    }

    private func pointDistance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}

private final class FogTile {
    let rect: CGRect
    let node: SKShapeNode
    var isExplored = false

    init(rect: CGRect, node: SKShapeNode) {
        self.rect = rect
        self.node = node
    }
}

private final class SealedDoor {
    let rect: CGRect
    let node: SKShapeNode
    private let scaleFactor: CGFloat
    private(set) var isOpen = false

    var center: CGPoint { rect.midPoint }

    init(rect: CGRect, scaleFactor: CGFloat, label: String) {
        self.rect = rect
        self.scaleFactor = scaleFactor
        node = SKShapeNode(rect: rect, cornerRadius: 2 * scaleFactor)
        node.fillColor = UIColor(red: 0.34, green: 0.16, blue: 0.12, alpha: 1)
        node.strokeColor = UIColor(red: 0.88, green: 0.39, blue: 0.21, alpha: 0.92)
        node.lineWidth = 1.6 * scaleFactor
        node.zPosition = 6
        node.name = label
        node.physicsBody = SKPhysicsBody(rectangleOf: rect.size, center: CGPoint(x: rect.midX, y: rect.midY))
        node.physicsBody?.isDynamic = false
        node.physicsBody?.categoryBitMask = PhysicsCategory.wall
        node.physicsBody?.collisionBitMask = PhysicsCategory.player | PhysicsCategory.hunter

        let tag = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        tag.text = label
        tag.fontSize = 6 * scaleFactor
        tag.fontColor = UIColor(white: 0.94, alpha: 0.84)
        tag.position = CGPoint(x: rect.midX, y: rect.midY + 1 * scaleFactor)
        tag.verticalAlignmentMode = .center
        tag.horizontalAlignmentMode = .center
        tag.zPosition = 1
        node.addChild(tag)
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        node.physicsBody = nil
        node.fillColor = UIColor(red: 0.16, green: 0.28, blue: 0.22, alpha: 0.62)
        node.strokeColor = UIColor(red: 0.48, green: 0.79, blue: 0.57, alpha: 0.72)
        node.run(.sequence([.fadeAlpha(to: 0.42, duration: 0.35)]))
    }
}

private extension CGRect {
    var midPoint: CGPoint { CGPoint(x: midX, y: midY) }
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
