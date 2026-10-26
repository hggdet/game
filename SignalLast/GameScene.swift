import SpriteKit
import UIKit

final class GameScene: SKScene {
    var onSnapshot: ((GameSnapshot) -> Void)?
    var onProgress: ((GameState) -> Void)?
    var onCheckpoint: ((GameCheckpoint) -> Void)?
    var onDebugModeChanged: ((Bool) -> Void)?

    private var scaleFactor: CGFloat = 1
    private var levelData = StationLevelData.standard
    private var worldLevelData = StationLevelData.standard
    private var roomBounds = CGRect.zero
    private var carpetRect = CGRect.zero
    private var glassRect = CGRect.zero
    private var pitchDarkRoomRect = CGRect.zero
    private var narrowCorridorRect = CGRect.zero
    private var transmissionRoomRect = CGRect.zero
    private var glassBroken = false
    private var hasBuiltWorld = false
    private var lastUpdateTime: TimeInterval = 0
    private var publishClock: TimeInterval = 0
    private var fogClock: TimeInterval = 0
    private var sceneClock: TimeInterval = 0
    private var habitClock: TimeInterval = 0
    private var ambientClock: TimeInterval = 0
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
    private var survivor: SurvivorNPC?
    private var survivorFollowing = false
    private var didFinish = false
    private var didLose = false
    private var isFinalChoicePending = false
    private var isWaitingInHiding = false
    private var hideWaitRemaining: TimeInterval = 30
    private var progressSaveClock: TimeInterval = 0
    private var transmissionInstalled = false
    private var transmissionProgress: TimeInterval = 0
    private var revealMapEnabled = false
    private var debugEnabled = false
    private var debugTapCount = 0
    private var lastDebugTapTime: TimeInterval = 0
    private var lastDebugNoiseNode: SKShapeNode?
    private var debugLabels: [String: SKLabelNode] = [:]
    private var gameState = GameState()
    private var earlyExitPosition = CGPoint.zero
    private var finalExitPosition = CGPoint.zero
    private let heartbeat = HeartbeatHaptics()

    private var player: Player?
    private var deathAngel: DeathAngelAI?
    private var demogorgon: DemogorgonAI?
    private var noiseSystem = NoiseSystem()
    private var flashlight = FlashlightSystem()
    private var monsterMemory = MonsterMemory()
    private var monsterDirector = MonsterDirector()
    private var flare: LitFlare?
    private var sealedDoors: [LevelDoorNode] = []
    private var fogTiles: [FogTile] = []
    private var roomOutlineNodes: [SKShapeNode] = []
    private var cameraNode: SKCameraNode?
    private var vignetteNode: SKShapeNode?
    private var transmissionConsole: SKShapeNode?

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        let viewSize = view.bounds.size
        if viewSize.width > 0, viewSize.height > 0 {
            let landscapeSize = CGSize(width: max(viewSize.width, viewSize.height), height: min(viewSize.width, viewSize.height))
            if size != landscapeSize { size = landscapeSize }
        }
        backgroundColor = UIColor(red: 0.006, green: 0.012, blue: 0.018, alpha: 1)
        physicsWorld.gravity = .zero
        physicsWorld.speed = 1
        if !hasBuiltWorld, gameState.hasStarted, size.width > 0, size.height > 0 { buildWorld() }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        if size.width < size.height {
            let landscapeSize = CGSize(width: size.height, height: size.width)
            if size != landscapeSize { size = landscapeSize }
            return
        }
        guard hasBuiltWorld, oldSize != .zero else { return }
        buildWorld()
    }

    func setMovementInput(_ input: CGVector) {
        player?.movementInput = (isHiding || didFinish) ? .zero : input
    }

    func setSprintActive(_ isActive: Bool) {
        player?.sprintRequested = isActive && !isHiding && !didFinish
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

    func setRevealMap(_ enabled: Bool) {
        revealMapEnabled = enabled
        if enabled {
            fogTiles.forEach { $0.isExplored = true }
        }
        updateFogOfWar()
    }

    func setDebugMode(_ enabled: Bool) {
        setDebugEnabled(enabled)
    }

    func escapeEarly() {
        guard hasBuiltWorld, !didFinish, let player else { return }
        let canUseEarlyExit = collectedPartIDs.count < 5 && pointDistance(player.position, earlyExitPosition) <= 45 * scaleFactor
        let canAbortAtFinalExit = transmissionInstalled && pointDistance(player.position, finalExitPosition) <= 52 * scaleFactor
        guard canUseEarlyExit || canAbortAtFinalExit else { return }
        gameState.escapedEarly = true
        gameState.usedExit = true
        finish(with: .earlyEscape)
    }

    /// Installs the signal device when the player has all five parts and is at
    /// the terminal. The truth ending is earned only after ten active seconds.
    func chooseStationTruth() {
        guard hasBuiltWorld, !didFinish, !transmissionInstalled,
              collectedPartIDs.count == 5, let player,
              pointDistance(player.position, worldLevelData.spawns.transmission) <= 58 * scaleFactor else { return }
        installTransmission()
    }

    func chooseSacrificeLight() {
        guard isFinalChoicePending, !didFinish, !transmissionInstalled else { return }
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
        guard hasBuiltWorld, !didFinish, let player else { return }
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
        guard hasBuiltWorld, !didFinish, !survivorFollowing, let player, let survivor,
              pointDistance(survivor.position, player.position) <= 37 * scaleFactor else { return }
        survivorFollowing = true
        survivor.beginFollowing()
        noiseSystem.emit(
            source: .survivorFootstep,
            at: survivor.position,
            baseRadius: 235 * scaleFactor,
            surface: .metal,
            time: sceneClock
        )
        AudioManager.play(.doorRattle, at: survivor.position)
        publishSnapshot(forceSave: true)
    }

    func toggleFlashlight() {
        guard !didFinish else { return }
        flashlight.toggle()
        publishSnapshot()
    }

    func cycleFlashlightLevel() {
        guard !didFinish else { return }
        flashlight.cycleLevel()
        publishSnapshot()
    }

    func placeFlare() {
        guard hasBuiltWorld, !didFinish, let player else { return }
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

    /// Throws toward a sealed door within range; the impact event itself opens
    /// the door and remains a sound cue rather than an automatic interaction.
    func throwNoiseItem() {
        guard hasBuiltWorld, !didFinish, throwItemsRemaining > 0, let player else { return }
        throwItemsRemaining -= 1
        publishSnapshot()
        let nearestDoor = sealedDoors
            .filter { !$0.isOpen }
            .min { pointDistance($0.center, player.position) < pointDistance($1.center, player.position) }
        let canReachDoor = nearestDoor.map { pointDistance($0.center, player.position) <= 260 * scaleFactor } ?? false
        let impact: CGPoint
        if let nearestDoor, canReachDoor {
            impact = nearestDoor.center
        } else {
            impact = CGPoint(
                x: player.position.x + player.facingDirection.dx * 112 * scaleFactor,
                y: player.position.y + player.facingDirection.dy * 112 * scaleFactor
            )
        }

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
                surface: self.surface(at: impact),
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

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let cameraNode else { return }
        let point = touch.location(in: cameraNode)
        let isTopLeft = point.x <= -size.width * 0.32 && point.y >= size.height * 0.30
        guard isTopLeft else { debugTapCount = 0; return }
        if touch.timestamp - lastDebugTapTime > 0.72 { debugTapCount = 0 }
        lastDebugTapTime = touch.timestamp
        debugTapCount += 1
        if debugTapCount >= 3 {
            debugTapCount = 0
            setDebugEnabled(!debugEnabled)
        }
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

        if isHiding { player.movementInput = .zero }
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
        updateTransmission(delta: delta)
        if didFinish { return }

        AudioManager.setListenerPosition(player.position)
        ambientClock += delta
        if ambientClock >= 24 {
            ambientClock = 0
            AudioManager.play(.distantStationAmbience, at: offscreenAudioPoint())
        }
        fogClock += delta
        if fogClock >= 0.08 {
            fogClock = 0
            updateFogOfWar()
        }
        updateCamera(delta: delta)
        updateDebugNodes()
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
        guard size.width > 0, size.height > 0 else { return }
        hasBuiltWorld = false
        removeAllChildren()
        physicsWorld.removeAllJoints()
        physicsWorld.gravity = .zero

        scaleFactor = min(size.width / 844, size.height / 390)
        levelData = StationLevelData.standard
        worldLevelData = levelData.scaled(by: scaleFactor)
        roomBounds = worldLevelData.worldBounds
        carpetRect = worldLevelData.surfaceZone(id: "entrance-carpet")?.rect ?? .zero
        glassRect = worldLevelData.surfaceZone(id: "broken-glass")?.rect ?? .zero
        pitchDarkRoomRect = worldLevelData.room(id: "lab-a")?.rect ?? .zero
        narrowCorridorRect = worldLevelData.room(id: "metal-corridor")?.rect ?? .zero
        transmissionRoomRect = worldLevelData.room(id: "transmission-room")?.rect ?? .zero

        glassBroken = false
        lastUpdateTime = 0
        publishClock = 0
        fogClock = 0
        sceneClock = 0
        habitClock = 0
        ambientClock = 0
        progressSaveClock = 0
        isHiding = gameState.hasStarted && gameState.isHiding
        holdingBreath = false
        breathMeter = 0
        breathNoiseClock = 0
        lockerPositions = worldLevelData.lockers.map(\.center)
        activeLockerPosition = nil
        collectibleParts = []
        collectedPartIDs = gameState.hasStarted ? gameState.collectedPartIDs : []
        points = gameState.hasStarted ? gameState.points : 0
        throwItemsRemaining = gameState.hasStarted ? gameState.throwItemsRemaining : 3
        survivorFollowing = gameState.hasStarted && gameState.savedSurvivor
        didFinish = false
        didLose = false
        isWaitingInHiding = gameState.hasStarted && gameState.isWaitingInHiding
        hideWaitRemaining = gameState.hasStarted ? gameState.hideWaitRemaining : 30
        transmissionInstalled = gameState.hasStarted && (gameState.transmissionInstalled ?? false)
        transmissionProgress = gameState.hasStarted ? min(10, max(0, gameState.transmissionProgress ?? 0)) : 0
        isFinalChoicePending = gameState.hasStarted && gameState.isFinalChoicePending && !transmissionInstalled
        revealMapEnabled = GameStateStore.loadPreferences().revealMap ?? false

        flashlight = FlashlightSystem()
        if gameState.hasStarted, let savedLevel = FlashlightLevel(rawValue: gameState.flashlightLevel) {
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
        roomOutlineNodes = []
        lastDebugNoiseNode = nil
        debugLabels = [:]
        transmissionConsole = nil
        noiseSystem = NoiseSystem()

        let builtLevel = LevelBuilder.build(into: self, level: levelData, scaleFactor: scaleFactor, revealMap: revealMapEnabled)
        sealedDoors = builtLevel.doors
        for door in sealedDoors where gameState.openedDoorIDs?.contains(door.id) == true {
            door.open()
        }
        roomOutlineNodes = builtLevel.roomOutlineNodes
        roomOutlineNodes.forEach { $0.isHidden = !debugEnabled }
        addTutorialSigns()

        let entrance = worldLevelData.room(id: "entrance")?.rect ?? roomBounds.insetBy(dx: 70 * scaleFactor, dy: 180 * scaleFactor)
        earlyExitPosition = CGPoint(x: entrance.minX + 38 * scaleFactor, y: entrance.midY)
        finalExitPosition = CGPoint(x: transmissionRoomRect.maxX - 30 * scaleFactor, y: transmissionRoomRect.midY)
        addEmergencyExit(at: earlyExitPosition, title: "مخرج الطوارئ")
        addEmergencyExit(at: finalExitPosition, title: "مخرج الإرسال")
        addTransmissionConsole(at: worldLevelData.spawns.transmission)

        let newPlayer = Player(scaleFactor: scaleFactor)
        player = newPlayer
        newPlayer.position = restoredPlayerPosition(entrance: entrance)
        newPlayer.isHidden = isHiding
        if isHiding {
            let nearestLocker = lockerPositions.min { pointDistance($0, newPlayer.position) < pointDistance($1, newPlayer.position) }
            if let nearestLocker { newPlayer.position = nearestLocker; activeLockerPosition = nearestLocker }
        }
        addChild(newPlayer)

        let routes = [worldLevelData.demogorgonPatrolWaypoints, worldLevelData.deathAngelPatrolWaypoints]
        let habitZones = worldLevelData.rooms.map { ($0.id, $0.rect.midPoint) }
        habitZones.forEach { monsterMemory.registerZone($0.0, center: $0.1) }
        spawnCollectibleParts(patrolRoutes: routes)

        let newSurvivor = SurvivorNPC(scaleFactor: scaleFactor)
        survivor = newSurvivor
        newSurvivor.position = worldLevelData.spawns.survivor
        if survivorFollowing { newSurvivor.beginFollowing() }
        addChild(newSurvivor)

        let newDeathAngel = DeathAngelAI(
            scaleFactor: scaleFactor,
            patrolPoints: worldLevelData.deathAngelPatrolWaypoints,
            hidingSpots: lockerPositions,
            memory: monsterMemory
        )
        deathAngel = newDeathAngel
        newDeathAngel.position = worldLevelData.spawns.deathAngel
        newDeathAngel.setActive(false)
        newDeathAngel.onStateChange = { [weak self] _ in self?.publishSnapshot() }
        addChild(newDeathAngel)

        let newDemogorgon = DemogorgonAI(
            scaleFactor: scaleFactor,
            patrolPoints: worldLevelData.demogorgonPatrolWaypoints,
            hidingSpots: lockerPositions,
            memory: monsterMemory
        )
        demogorgon = newDemogorgon
        newDemogorgon.position = worldLevelData.spawns.demogorgon
        newDemogorgon.setActive(true)
        newDemogorgon.onStateChange = { [weak self] _ in self?.publishSnapshot() }
        addChild(newDemogorgon)

        if transmissionInstalled, let player {
            newDeathAngel.position = CGPoint(x: worldLevelData.spawns.transmission.x - 110 * scaleFactor, y: worldLevelData.spawns.transmission.y)
            newDeathAngel.beginFinalHunt(at: player.position)
            newDemogorgon.position = CGPoint(x: worldLevelData.spawns.transmission.x + 110 * scaleFactor, y: worldLevelData.spawns.transmission.y)
            newDemogorgon.beginFinalHunt(at: player.position)
        }

        noiseSystem.onNoise = { [weak self] event in
            guard let self else { return }
            let doorOpened = self.openDoorIfHit(by: event)
            let entrance = self.worldLevelData.room(id: "entrance")?.rect ?? .zero
            let isTutorialNoise = entrance.insetBy(dx: -180 * self.scaleFactor, dy: -120 * self.scaleFactor).contains(event.position)
            if !isTutorialNoise {
                self.deathAngel?.hear(event)
                if event.radius >= 300 * self.scaleFactor {
                    self.monsterDirector.notifyLoudNoise()
                }
            }
            if doorOpened { AudioManager.play(.doorRattle, at: event.position) }
            self.updateDebugNoise(event)
            self.publishSnapshot()
        }

        configureMonsterDirector()
        createFogTiles()
        configureCameraFeedback()
        hasBuiltWorld = true
        gameState.hasStarted = true
        if collectedPartIDs.count >= 5 && !transmissionInstalled { isFinalChoicePending = true }
        updateFogOfWar()
        cameraNode?.position = newPlayer.position
        AudioManager.setListenerPosition(newPlayer.position)
        AudioManager.play(.distantStationAmbience, at: offscreenAudioPoint())
        publishSnapshot()
        flushProgress()
    }

    private func restoredPlayerPosition(entrance: CGRect) -> CGPoint {
        guard gameState.hasStarted else { return worldLevelData.spawns.player }
        let xRatio = CGFloat(gameState.playerXRatio)
        let yRatio = CGFloat(gameState.playerYRatio)
        let bounds: CGRect
        if (gameState.levelLayoutVersion ?? 0) >= 1 {
            bounds = roomBounds
        } else {
            // Earlier saves used a single-room coordinate space; map them into
            // the safe entrance so progress survives this layout expansion.
            bounds = entrance
        }
        let point = CGPoint(x: bounds.minX + bounds.width * xRatio, y: bounds.minY + bounds.height * yRatio)
        let safeBounds = roomBounds.insetBy(dx: 34 * scaleFactor, dy: 34 * scaleFactor)
        return CGPoint(x: min(max(point.x, safeBounds.minX), safeBounds.maxX), y: min(max(point.y, safeBounds.minY), safeBounds.maxY))
    }

    private func addTutorialSigns() {
        guard let entrance = worldLevelData.room(id: "entrance") else { return }
        addLabel("حرّك العصا للتسلّل أو المشي", at: CGPoint(x: entrance.rect.midX, y: entrance.rect.maxY - 50 * scaleFactor), size: 12 * scaleFactor, color: UIColor(red: 0.72, green: 0.91, blue: 0.93, alpha: 0.92))
        addLabel("اضغط مطولاً على «ركض» — الصوت يجذب الخطر", at: CGPoint(x: entrance.rect.midX, y: entrance.rect.maxY - 72 * scaleFactor), size: 9 * scaleFactor, color: UIColor(red: 0.75, green: 0.82, blue: 0.83, alpha: 0.82))
        addLabel("المصباح · الرمي · الاختباء · الإنقاذ", at: CGPoint(x: entrance.rect.midX, y: entrance.rect.maxY - 91 * scaleFactor), size: 8.5 * scaleFactor, color: UIColor(red: 0.68, green: 0.81, blue: 0.83, alpha: 0.75))
    }

    private func addEmergencyExit(at point: CGPoint, title: String) {
        let door = SKShapeNode(rectOf: CGSize(width: 42 * scaleFactor, height: 15 * scaleFactor), cornerRadius: 4 * scaleFactor)
        door.name = "emergencyExit"
        door.position = point
        door.fillColor = UIColor(red: 0.06, green: 0.37, blue: 0.31, alpha: 0.96)
        door.strokeColor = UIColor(red: 0.38, green: 0.97, blue: 0.74, alpha: 0.95)
        door.lineWidth = 1.5 * scaleFactor
        door.glowWidth = 7 * scaleFactor
        door.zPosition = 31
        addChild(door)
        addLabel(title, at: CGPoint(x: point.x, y: point.y - 18 * scaleFactor), size: 7.5 * scaleFactor, color: UIColor(red: 0.64, green: 1, blue: 0.83, alpha: 0.95))
    }

    private func addTransmissionConsole(at point: CGPoint) {
        let console = SKShapeNode(rectOf: CGSize(width: 50 * scaleFactor, height: 32 * scaleFactor), cornerRadius: 6 * scaleFactor)
        console.position = point
        console.fillColor = UIColor(red: 0.06, green: 0.20, blue: 0.23, alpha: 0.96)
        console.strokeColor = UIColor(red: 0.24, green: 0.82, blue: 0.88, alpha: 0.96)
        console.lineWidth = 1.5 * scaleFactor
        console.glowWidth = 7 * scaleFactor
        console.zPosition = 5
        console.name = "transmissionConsole"
        addChild(console)
        addLabel("جهاز الإرسال", at: CGPoint(x: point.x, y: point.y - 26 * scaleFactor), size: 8 * scaleFactor, color: UIColor(red: 0.63, green: 0.92, blue: 0.95, alpha: 0.9))
        let light = SKShapeNode(circleOfRadius: 3 * scaleFactor)
        light.fillColor = UIColor.cyan
        light.strokeColor = .clear
        light.position = CGPoint(x: point.x, y: point.y + 5 * scaleFactor)
        light.zPosition = 7
        addChild(light)
        transmissionConsole = console
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
        for placement in worldLevelData.pickups {
            guard !collectedPartIDs.contains(placement.id) else { continue }
            let routeDistance = patrolRoutes.flatMap { route in
                route.indices.map { index in
                    distance(placement.position, toSegmentFrom: route[index], to: route[(index + 1) % route.count])
                }
            }.min() ?? .greatestFiniteMagnitude
            let value = routeDistance <= 90 * scaleFactor ? 3 : (routeDistance <= 190 * scaleFactor ? 2 : 1)
            let part = CollectiblePart(index: placement.id, pointValue: value, isNoisy: placement.isNoisy, scaleFactor: scaleFactor)
            part.position = placement.position
            collectibleParts.append(part)
            addChild(part)
            if placement.isNoisy {
                addLabel(placement.title.isEmpty ? "بطارية معدنية" : placement.title, at: CGPoint(x: placement.position.x, y: placement.position.y - 24 * scaleFactor), size: 6.5 * scaleFactor, color: UIColor(red: 1, green: 0.76, blue: 0.45, alpha: 0.9))
            }
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
        guard !didFinish, !transmissionInstalled, let player else { return }
        let collected = collectibleParts.filter { pointDistance(player.position, $0.position) <= 22 * scaleFactor }
        guard !collected.isEmpty else { return }
        for part in collected {
            collectedPartIDs.insert(part.index)
            points += part.pointValue
            if part.isNoisy {
                if part.index == 3 { flashlight.recharge(by: 45) }
                let baseRadius: CGFloat = part.index == 3 ? 520 * scaleFactor : 310 * scaleFactor
                noiseSystem.emit(
                    source: .loudPickup,
                    at: part.position,
                    baseRadius: baseRadius,
                    surface: .metal,
                    time: sceneClock
                )
                AudioManager.play(.doorRattle, at: part.position)
            }
            part.removeFromParent()
            collectibleParts.removeAll { $0 === part }
        }
        if collectedPartIDs.count >= 5 {
            isFinalChoicePending = true
            if survivorFollowing {
                finish(with: .tragic)
                return
            }
        }
        publishSnapshot(forceSave: true)
        if collected.contains(where: { $0.index == 3 }) {
            saveCheckpoint(.afterPartThree)
        }
    }

    private func updateSurvivorFollower(delta: TimeInterval) {
        guard survivorFollowing, let survivor, let player else { return }
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
        guard let player, let deathAngel, let demogorgon else { return }
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
        guard let player else { return }
        let origin = activeLockerPosition ?? player.position
        noiseSystem.emit(source: .breathing, at: origin, baseRadius: 155 * scaleFactor, surface: .metal, time: sceneClock)
    }

    private func canEnterNearbyLocker() -> Bool {
        if isHiding { return true }
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
        if worldLevelData.surfaceZones.first(where: { $0.rect.contains(point) })?.surface == .glass { return .glass }
        if worldLevelData.surfaceZones.first(where: { $0.rect.contains(point) })?.surface == .carpet { return .carpet }
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
        if door.id == "door-1" {
            saveCheckpoint(.afterDoorOne)
        }
        return true
    }

    private func installTransmission() {
        guard let player, let deathAngel, let demogorgon else { return }
        transmissionInstalled = true
        transmissionProgress = max(0, transmissionProgress)
        isFinalChoicePending = false
        player.movementInput = .zero
        transmissionConsole?.strokeColor = UIColor(red: 0.96, green: 0.73, blue: 0.30, alpha: 1)
        AudioManager.play(.transmissionStart, at: worldLevelData.spawns.transmission)

        // The signal draws both hunters to the terminal. They remain active at
        // the same time for the full 10-second transmission attempt.
        deathAngel.position = CGPoint(x: worldLevelData.spawns.transmission.x - 110 * scaleFactor, y: worldLevelData.spawns.transmission.y)
        deathAngel.setActive(true)
        deathAngel.beginFinalHunt(at: player.position)
        demogorgon.position = CGPoint(x: worldLevelData.spawns.transmission.x + 110 * scaleFactor, y: worldLevelData.spawns.transmission.y)
        demogorgon.setActive(true)
        demogorgon.beginFinalHunt(at: player.position)
        publishSnapshot(forceSave: true)
    }

    private func updateTransmission(delta: TimeInterval) {
        guard transmissionInstalled, let player else { return }
        let conditionsHold = flashlight.isOn && flashlight.level == .strong && hasRecentLoudTransmissionNoise()
        if conditionsHold { transmissionProgress = min(10, transmissionProgress + max(0, delta)) }
        if transmissionProgress >= 10 {
            AudioManager.play(.transmissionComplete, at: player.position)
            finish(with: .stationTruth)
        }
    }

    private func hasRecentLoudTransmissionNoise() -> Bool {
        guard let event = noiseSystem.latestEvent else { return false }
        return sceneClock - event.timestamp <= 0.50
            && event.radius >= 280 * scaleFactor
            && (event.source == .runningFootstep || event.source == .glassBreak || event.source == .thrownItem || event.source == .loudPickup)
    }

    private func configureMonsterDirector() {
        monsterDirector.onBuildUpSound = { [weak self] secondCue in
            guard let self else { return }
            AudioManager.play(secondCue ? .doorRattle : .distantFootsteps, at: self.offscreenAudioPoint())
        }
        // The director controls pressure messaging and audio timing. The
        // Demogorgon keeps its Lab patrol; the Death Angel is awakened only by
        // thresholded noise and sleeps again after losing the trail.
        monsterDirector.onAttack = { [weak self] _ in self?.publishSnapshot() }
        monsterDirector.onRetreat = { [weak self] in self?.publishSnapshot() }
        monsterDirector.onPhaseChange = { [weak self] phase in
            guard let self else { return }
            self.publishSnapshot()
            if phase == .calm { AudioManager.play(.distantStationAmbience, at: self.offscreenAudioPoint()) }
        }
    }

    private func offscreenAudioPoint() -> CGPoint {
        guard let player else { return roomBounds.midPoint }
        let candidates = [
            CGPoint(x: roomBounds.minX + 36 * scaleFactor, y: roomBounds.midY),
            CGPoint(x: roomBounds.maxX - 36 * scaleFactor, y: roomBounds.midY),
            CGPoint(x: roomBounds.midX, y: roomBounds.maxY - 36 * scaleFactor),
            CGPoint(x: roomBounds.midX, y: roomBounds.minY + 36 * scaleFactor)
        ]
        return candidates.max { pointDistance($0, player.position) < pointDistance($1, player.position) } ?? roomBounds.midPoint
    }

    private func updatePlayerHabit(delta: TimeInterval) {
        habitClock += delta
        guard habitClock >= 1.2 else { return }
        habitClock = 0
        guard let player, player.speedMode == .run || flashlight.isOn else { return }
        let room = worldLevelData.rooms.first(where: { $0.rect.contains(player.position) })
        if let room { monsterMemory.recordUse(in: room.id) }
    }

    private func createFogTiles() {
        fogTiles = []
        let tileSize = 96 * scaleFactor
        let columns = max(1, Int(ceil(roomBounds.width / tileSize)))
        let rows = max(1, Int(ceil(roomBounds.height / tileSize)))
        let tileWidth = roomBounds.width / CGFloat(columns)
        let tileHeight = roomBounds.height / CGFloat(rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let rect = CGRect(
                    x: roomBounds.minX + CGFloat(column) * tileWidth,
                    y: roomBounds.minY + CGFloat(row) * tileHeight,
                    width: tileWidth + 0.8,
                    height: tileHeight + 0.8
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
        if revealMapEnabled { fogTiles.forEach { $0.isExplored = true } }
    }

    private func updateFogOfWar() {
        guard let player else { return }
        let facingAngle = atan2(player.facingDirection.dy, player.facingDirection.dx)
        for tile in fogTiles {
            if revealMapEnabled {
                tile.node.alpha = 0.06
                continue
            }
            let point = tile.rect.midPoint
            let dx = point.x - player.position.x
            let dy = point.y - player.position.y
            let distance = hypot(dx, dy)
            let angle = atan2(dy, dx)
            let angleDifference = abs(atan2(sin(angle - facingAngle), cos(angle - facingAngle)))
            let visible = flashlight.isOn && (distance <= 27 * scaleFactor || (distance <= flashlight.level.revealRange * scaleFactor && angleDifference <= 0.68))
            if visible { tile.isExplored = true }
            let targetAlpha: CGFloat = visible ? 0.04 : (tile.isExplored ? 0.69 : 0.97)
            tile.node.alpha = targetAlpha
        }
    }

    private func configureCameraFeedback() {
        let newCamera = SKCameraNode()
        newCamera.position = player?.position ?? roomBounds.midPoint
        addChild(newCamera)
        cameraNode = newCamera
        camera = newCamera

        let newVignette = SKShapeNode(rectOf: size, cornerRadius: 24 * scaleFactor)
        newVignette.position = .zero
        newVignette.fillColor = UIColor(red: 0.48, green: 0.035, blue: 0.025, alpha: 0)
        newVignette.strokeColor = UIColor(red: 0.88, green: 0.08, blue: 0.035, alpha: 0)
        newVignette.lineWidth = 26 * scaleFactor
        newVignette.glowWidth = 15 * scaleFactor
        newVignette.zPosition = 100
        vignetteNode = newVignette
        newCamera.addChild(newVignette)
    }

    private func updateCamera(delta: TimeInterval) {
        guard let player, let cameraNode else { return }
        let halfWidth = size.width * 0.5
        let halfHeight = size.height * 0.5
        let targetX = min(max(player.position.x, roomBounds.minX + halfWidth), roomBounds.maxX - halfWidth)
        let targetY = min(max(player.position.y, roomBounds.minY + halfHeight), roomBounds.maxY - halfHeight)
        let smoothing = min(1, max(0, CGFloat(delta) * 7.5))
        cameraNode.position = CGPoint(
            x: cameraNode.position.x + (targetX - cameraNode.position.x) * smoothing,
            y: cameraNode.position.y + (targetY - cameraNode.position.y) * smoothing
        )
    }

    private func setDebugEnabled(_ enabled: Bool) {
        guard debugEnabled != enabled else { return }
        debugEnabled = enabled
        onDebugModeChanged?(enabled)
        roomOutlineNodes.forEach { $0.isHidden = !enabled }
        if !enabled {
            lastDebugNoiseNode?.removeFromParent()
            lastDebugNoiseNode = nil
            debugLabels.values.forEach { $0.removeFromParent() }
            debugLabels.removeAll()
        } else {
            updateDebugNodes()
        }
    }

    private func updateDebugNoise(_ event: NoiseEvent) {
        guard debugEnabled else { return }
        lastDebugNoiseNode?.removeFromParent()
        let radius = SKShapeNode(circleOfRadius: event.radius)
        radius.position = event.position
        radius.fillColor = UIColor(red: 0.95, green: 0.60, blue: 0.15, alpha: 0.08)
        radius.strokeColor = UIColor(red: 1, green: 0.70, blue: 0.24, alpha: 0.85)
        radius.lineWidth = 1.4 * scaleFactor
        radius.zPosition = 47
        addChild(radius)
        lastDebugNoiseNode = radius
    }

    private func updateDebugNodes() {
        guard debugEnabled else { return }
        if let deathAngel {
            let label = debugLabel(for: "deathAngel", title: "DA · \(deathAngel.state.arabicTitle)")
            label.position = CGPoint(x: deathAngel.position.x, y: deathAngel.position.y + 42 * scaleFactor)
        }
        if let demogorgon {
            let label = debugLabel(for: "demogorgon", title: "DG · \(demogorgon.state.arabicTitle)")
            label.position = CGPoint(x: demogorgon.position.x, y: demogorgon.position.y + 45 * scaleFactor)
        }
        if let player {
            let label = debugLabel(for: "director", title: "Director · \(monsterDirector.phase.arabicTitle)")
            label.position = CGPoint(x: player.position.x, y: player.position.y + 28 * scaleFactor)
        }
    }

    private func debugLabel(for id: String, title: String) -> SKLabelNode {
        if let existing = debugLabels[id] {
            existing.text = title
            return existing
        }
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = title
        label.fontSize = 8 * scaleFactor
        label.fontColor = .yellow
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.zPosition = 48
        addChild(label)
        debugLabels[id] = label
        return label
    }

    private func updateThreatFeedback(delta: TimeInterval) {
        guard let player, let cameraNode, let vignetteNode else { return }
        let threat = threatLevel()
        heartbeat.update(threat: threat, delta: delta)
        let pulse = 0.5 + 0.5 * CGFloat(sin(sceneClock * 7.5))
        vignetteNode.fillColor = UIColor(red: 0.48, green: 0.035, blue: 0.025, alpha: threat * 0.075 * pulse)
        vignetteNode.strokeColor = UIColor(red: 0.88, green: 0.08, blue: 0.035, alpha: threat * (0.10 + 0.22 * pulse))
        let shake = threat * 5 * scaleFactor
        let halfWidth = size.width * 0.5
        let halfHeight = size.height * 0.5
        let targetX = min(max(player.position.x, roomBounds.minX + halfWidth), roomBounds.maxX - halfWidth)
        let targetY = min(max(player.position.y, roomBounds.minY + halfHeight), roomBounds.maxY - halfHeight)
        cameraNode.position = CGPoint(x: targetX + sin(sceneClock * 31) * shake, y: targetY + cos(sceneClock * 27) * shake)
    }

    private func publishSnapshot(forceSave: Bool = false) {
        guard hasBuiltWorld, let player, let deathAngel, let demogorgon else { return }
        let activeNoise = noiseSystem.latestEvent.flatMap { sceneClock - $0.timestamp < 3.0 ? $0 : nil }
        let intensity = min((activeNoise?.radius ?? 0) / (520 * scaleFactor), 1)
        let canEscapeAtStart = collectedPartIDs.count < 5 && pointDistance(player.position, earlyExitPosition) <= 45 * scaleFactor
        let canEscapeAfterTransmission = transmissionInstalled && pointDistance(player.position, finalExitPosition) <= 52 * scaleFactor
        let canInstall = collectedPartIDs.count == 5 && !transmissionInstalled && pointDistance(player.position, worldLevelData.spawns.transmission) <= 58 * scaleFactor
        let message: String

        if didFinish {
            message = didLose ? "أمسك بك أحد الصيادين. حاول من جديد، وراقب الضوء والصوت." : (gameState.ending?.message ?? "انتهت الجولة.")
        } else if transmissionInstalled {
            let conditions = flashlight.isOn && flashlight.level == .strong && hasRecentLoudTransmissionNoise()
            message = conditions ? "الإرسال جارٍ؛ حافظ على الضوء القوي والركض الصاخب." : "الإرسال متوقف مؤقتاً؛ تحتاج إلى ضوء قوي وصوت عالٍ معاً."
        } else if collectedPartIDs.count == 5 && !canInstall {
            message = "اكتملت الأجزاء. اتجه إلى غرفة الإرسال وركّب الجهاز؛ يمكنك الهرب إلى المخرج أيضاً."
        } else if canInstall {
            message = "ركّب جهاز الإرسال. سيهاجم الوحشان معاً؛ اركض وأبقِ المصباح قوياً لعشر ثوانٍ."
        } else if isWaitingInHiding {
            message = "ابقَ في الخزانة حتى تنقطع الإشارة: \(Int(ceil(hideWaitRemaining)))ث."
        } else if isHiding {
            message = holdingBreath ? "أنت داخل الخزانة. احبس نفسك ما دام عدّاد النفس يسمح." : "الخزانة تخفيك عن نظر Demogorgon؛ Death Angel ما زال يسمعك."
        } else if survivorFollowing {
            message = "الناجي يتبعك ويبطئك؛ خطواته قد تجذب Death Angel."
        } else if let entrance = worldLevelData.room(id: "entrance"), entrance.rect.insetBy(dx: -150 * scaleFactor, dy: -120 * scaleFactor).contains(player.position), sealedDoors.contains(where: { $0.id == "door-1" && !$0.isOpen }) {
            message = "الباب مختوم. ارمِ غرضاً ليصطدم به؛ الضوضاء تفتحه."
        } else if player.position.x < worldLevelData.spawns.deathAngel.x - 700 * scaleFactor {
            message = "المدخل آمن. القطع الصامتة لا توقظ الوحوش البعيدة."
        } else if monsterDirector.phase == .buildUp {
            message = "أصوات بعيدة… سيصمت المكان قبل دخول الوحش."
        } else if monsterDirector.phase == .retreat {
            message = "انسحب الخطر. استغل الهدوء وراقب البطارية."
        } else if demogorgon.state == .chase {
            message = "Demogorgon يلاحق الضوء؛ أطفئ المصباح وغيّر موقعك."
        } else if deathAngel.state == .chase || deathAngel.state == .investigate {
            message = "Death Angel سمع ضوضاء ويتجه إلى مصدرها؛ غيّر موقعك."
        } else if pitchDarkRoomRect.contains(player.position) && !flashlight.isOn {
            message = "المختبر مظلم تماماً. شغّل المصباح بحذر لتكشف الطريق."
        } else if glassRect.contains(player.position) {
            message = "زجاج مكسور: حتى المشي البطيء يصدر ضوضاء خطرة."
        } else if carpetRect.contains(player.position) {
            message = "السجاد يخفت الخطوات؛ اختبر الركض هنا بأمان."
        } else if monsterDirector.phase == .calm {
            message = flashlight.isOn ? "هدوء مؤقت… الضوء قد يجذب Demogorgon." : "في الظلام لا يراك Demogorgon إلا عن قرب."
        } else {
            message = "تحرّك بتسلل، واحفظ البطارية للأماكن المظلمة."
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
            canEscapeEarly: !didFinish && (canEscapeAtStart || canEscapeAfterTransmission),
            isWaitingInHiding: isWaitingInHiding,
            hideWaitRemaining: hideWaitRemaining,
            transmissionInstalled: transmissionInstalled,
            transmissionProgress: CGFloat(transmissionProgress / 10),
            canInstallTransmission: canInstall,
            didFinish: didFinish,
            didLose: didLose,
            ending: gameState.ending
        ))
        if forceSave { onProgress?(gameState) }
    }

    private func updateStoredRunState() {
        guard let player, roomBounds.width > 0, roomBounds.height > 0 else { return }
        gameState.hasStarted = true
        gameState.levelLayoutVersion = 1
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
        gameState.transmissionInstalled = transmissionInstalled
        gameState.transmissionProgress = transmissionProgress
        gameState.openedDoorIDs = Set(sealedDoors.filter(\.isOpen).map(\.id))
        if gameState.usedExit == nil { gameState.usedExit = false }
        gameState.didDie = didLose
    }

    private func saveCheckpoint(_ milestone: CheckpointMilestone) {
        updateStoredRunState()
        let checkpoint = GameCheckpoint(milestone: milestone, state: gameState)
        onCheckpoint?(checkpoint)
        onProgress?(gameState)
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
        gameState.transmissionCompleted = ending == .stationTruth
        if ending == .earlyEscape {
            gameState.escapedEarly = true
            gameState.usedExit = true
        }
        if ending == .ambiguous { gameState.hidUntilEnd = true }
        publishSnapshot(forceSave: true)
    }

    private func checkForMonsterCapture() -> Bool {
        guard !didFinish, !isHiding, let player, let deathAngel, let demogorgon else { return false }
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
        if let deathAngel, deathAngel.isActive {
            threat = max(threat, max(0, 1 - pointDistance(player.position, deathAngel.position) / (300 * scaleFactor)))
        }
        if let demogorgon, demogorgon.isActive {
            threat = max(threat, max(0, 1 - pointDistance(player.position, demogorgon.position) / (300 * scaleFactor)))
        }
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

private extension CGRect {
    var midPoint: CGPoint { CGPoint(x: midX, y: midY) }
}
