import SpriteKit
import UIKit

struct LevelBuildResult {
    let doors: [LevelDoorNode]
    let roomOutlineNodes: [SKShapeNode]
    let surfaceZoneNodes: [SKNode]
}

final class LevelDoorNode: SKShapeNode {
    let id: String
    var center: CGPoint {
        get { position }
        set { position = newValue }
    }
    private(set) var isOpen: Bool

    private let scaledSize: CGSize
    private let scaledTitle: String

    init(layout: LevelDoorLayout, scaleFactor: CGFloat) {
        id = layout.id
        isOpen = layout.isInitiallyOpen
        scaledSize = CGSize(width: layout.rect.width * scaleFactor, height: layout.rect.height * scaleFactor)
        scaledTitle = layout.title
        let shapeRect = CGRect(x: -scaledSize.width / 2, y: -scaledSize.height / 2, width: scaledSize.width, height: scaledSize.height)
        super.init(rect: shapeRect, cornerRadius: max(2, 3 * scaleFactor))

        name = "door-\(id)"
        position = CGPoint(x: (layout.rect.midX * scaleFactor), y: (layout.rect.midY * scaleFactor))
        fillColor = UIColor(red: 0.28, green: 0.105, blue: 0.085, alpha: 0.98)
        strokeColor = UIColor(red: 0.94, green: 0.37, blue: 0.20, alpha: 0.96)
        lineWidth = max(1, 1.8 * scaleFactor)
        glowWidth = 3 * scaleFactor
        zPosition = 12
        physicsBody = isOpen ? nil : makePhysicsBody()

        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = scaledTitle
        label.fontSize = 8 * scaleFactor
        label.fontColor = UIColor(white: 0.94, alpha: 0.9)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 1
        addChild(label)

        if isOpen {
            fillColor = UIColor(red: 0.12, green: 0.24, blue: 0.18, alpha: 0.62)
            strokeColor = UIColor(red: 0.39, green: 0.78, blue: 0.53, alpha: 0.76)
            alpha = 0.56
        }
    }

    required init?(coder: NSCoder) {
        id = "restored-door"
        isOpen = true
        scaledSize = .zero
        scaledTitle = ""
        super.init(coder: coder)
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        physicsBody = nil
        fillColor = UIColor(red: 0.12, green: 0.24, blue: 0.18, alpha: 0.62)
        strokeColor = UIColor(red: 0.39, green: 0.78, blue: 0.53, alpha: 0.76)
        run(.fadeAlpha(to: 0.56, duration: 0.35))
    }

    private func makePhysicsBody() -> SKPhysicsBody {
        let body = SKPhysicsBody(rectangleOf: scaledSize)
        body.isDynamic = false
        body.affectedByGravity = false
        body.categoryBitMask = PhysicsCategory.wall
        body.collisionBitMask = PhysicsCategory.player | PhysicsCategory.hunter | PhysicsCategory.companion
        body.contactTestBitMask = 0
        return body
    }
}

enum LevelBuilder {
    static func build(into scene: SKScene, level: StationLevelData, scaleFactor: CGFloat, revealMap: Bool) -> LevelBuildResult {
        // The scene owns visibility fog; revealMap is intentionally not used to construct or alter fog here.
        _ = revealMap
        let scaledLevel = level.scaled(by: scaleFactor)
        let safeScale = max(0.01, abs(scaleFactor))
        var roomOutlineNodes: [SKShapeNode] = []
        var surfaceZoneNodes: [SKNode] = []

        let worldFloor = SKShapeNode(rect: scaledLevel.worldBounds)
        worldFloor.name = "station-world-floor"
        worldFloor.fillColor = UIColor(red: 0.012, green: 0.020, blue: 0.025, alpha: 1)
        worldFloor.strokeColor = .clear
        worldFloor.zPosition = -2
        scene.addChild(worldFloor)

        for room in scaledLevel.rooms {
            let floor = SKShapeNode(rect: room.rect, cornerRadius: 8 * safeScale)
            floor.name = "floor-\(room.id)"
            floor.fillColor = roomFloorColor(for: room.id)
            floor.strokeColor = UIColor(red: 0.18, green: 0.31, blue: 0.35, alpha: 0.72)
            floor.lineWidth = 1.15 * safeScale
            floor.zPosition = 0
            scene.addChild(floor)

            let subtleInnerEdge = SKShapeNode(rect: room.rect.insetBy(dx: 7 * safeScale, dy: 7 * safeScale), cornerRadius: 5 * safeScale)
            subtleInnerEdge.fillColor = .clear
            subtleInnerEdge.strokeColor = UIColor(red: 0.15, green: 0.29, blue: 0.33, alpha: 0.22)
            subtleInnerEdge.lineWidth = 0.7 * safeScale
            subtleInnerEdge.zPosition = 1
            scene.addChild(subtleInnerEdge)

            let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            label.text = room.title
            label.position = CGPoint(x: room.rect.midX, y: room.rect.midY)
            label.fontSize = 15 * safeScale
            label.fontColor = UIColor(white: 0.72, alpha: 0.52)
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.zPosition = 2
            label.name = "room-label-\(room.id)"
            scene.addChild(label)

            let outline = SKShapeNode(rect: room.rect, cornerRadius: 8 * safeScale)
            outline.name = "room-outline-\(room.id)"
            outline.fillColor = .clear
            outline.strokeColor = UIColor(red: 0.20, green: 0.86, blue: 0.91, alpha: 0.9)
            outline.lineWidth = 2 * safeScale
            outline.zPosition = 44
            outline.isHidden = true
            roomOutlineNodes.append(outline)
            scene.addChild(outline)
        }

        for rect in scaledLevel.wallRects {
            let wall = SKShapeNode(rect: rect, cornerRadius: 2 * safeScale)
            wall.name = "station-wall"
            wall.fillColor = UIColor(red: 0.12, green: 0.20, blue: 0.23, alpha: 0.98)
            wall.strokeColor = UIColor(red: 0.28, green: 0.43, blue: 0.47, alpha: 0.86)
            wall.lineWidth = max(0.7, 1 * safeScale)
            wall.zPosition = 8
            let body = SKPhysicsBody(rectangleOf: rect.size, center: CGPoint(x: rect.midX, y: rect.midY))
            body.isDynamic = false
            body.affectedByGravity = false
            body.categoryBitMask = PhysicsCategory.wall
            body.collisionBitMask = PhysicsCategory.player | PhysicsCategory.hunter | PhysicsCategory.companion
            body.contactTestBitMask = 0
            wall.physicsBody = body
            scene.addChild(wall)
        }

        let boundary = SKNode()
        boundary.name = "station-world-edge"
        let boundaryBody = SKPhysicsBody(edgeLoopFrom: scaledLevel.worldBounds)
        boundaryBody.isDynamic = false
        boundaryBody.categoryBitMask = PhysicsCategory.wall
        boundaryBody.collisionBitMask = PhysicsCategory.player | PhysicsCategory.hunter | PhysicsCategory.companion
        boundary.physicsBody = boundaryBody
        scene.addChild(boundary)

        for zone in scaledLevel.surfaceZones {
            let visual = SKShapeNode(rect: zone.rect, cornerRadius: 5 * safeScale)
            visual.name = "surface-zone-\(zone.id)"
            visual.fillColor = surfaceFillColor(zone.surface)
            visual.strokeColor = surfaceStrokeColor(zone.surface)
            visual.lineWidth = 1.1 * safeScale
            visual.zPosition = 3

            if zone.surface == .glass {
                addGlassGlimmers(to: visual, rect: zone.rect, scale: safeScale)
            } else if zone.surface == .carpet {
                addCarpetStitching(to: visual, rect: zone.rect, scale: safeScale)
            }

            let label = SKLabelNode(fontNamed: "AvenirNext-Medium")
            label.text = zone.title
            label.position = CGPoint(x: zone.rect.midX, y: zone.rect.midY)
            label.fontSize = 9 * safeScale
            label.fontColor = UIColor(white: 0.93, alpha: 0.82)
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.zPosition = 1
            visual.addChild(label)
            scene.addChild(visual)
            surfaceZoneNodes.append(visual)
        }

        addLockerVisuals(scaledLevel.lockers, to: scene, scale: safeScale)
        let doors = level.doors.map { layout -> LevelDoorNode in
            let door = LevelDoorNode(layout: layout, scaleFactor: scaleFactor)
            scene.addChild(door)
            return door
        }
        return LevelBuildResult(doors: doors, roomOutlineNodes: roomOutlineNodes, surfaceZoneNodes: surfaceZoneNodes)
    }

    private static func roomFloorColor(for id: String) -> UIColor {
        switch id {
        case "lab-a": return UIColor(red: 0.008, green: 0.015, blue: 0.021, alpha: 1)
        case "metal-corridor": return UIColor(red: 0.045, green: 0.035, blue: 0.034, alpha: 1)
        case "transmission-room": return UIColor(red: 0.021, green: 0.047, blue: 0.052, alpha: 1)
        default: return UIColor(red: 0.025, green: 0.046, blue: 0.055, alpha: 1)
        }
    }

    private static func surfaceFillColor(_ surface: NoiseSurface) -> UIColor {
        switch surface {
        case .carpet: return UIColor(red: 0.16, green: 0.27, blue: 0.28, alpha: 0.48)
        case .metal: return UIColor(red: 0.28, green: 0.17, blue: 0.12, alpha: 0.42)
        case .glass: return UIColor(red: 0.21, green: 0.39, blue: 0.46, alpha: 0.46)
        }
    }

    private static func surfaceStrokeColor(_ surface: NoiseSurface) -> UIColor {
        switch surface {
        case .carpet: return UIColor(red: 0.43, green: 0.67, blue: 0.64, alpha: 0.43)
        case .metal: return UIColor(red: 0.79, green: 0.43, blue: 0.29, alpha: 0.54)
        case .glass: return UIColor(red: 0.54, green: 0.82, blue: 0.93, alpha: 0.82)
        }
    }

    private static func addGlassGlimmers(to node: SKShapeNode, rect: CGRect, scale: CGFloat) {
        for index in 0..<7 {
            let x = rect.minX + rect.width * CGFloat(index + 1) / 8
            let y = rect.minY + rect.height * CGFloat((index * 3 % 7) + 1) / 8
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x - 4 * scale, y: y - 1 * scale))
            path.addLine(to: CGPoint(x: x + 3 * scale, y: y + 2 * scale))
            path.addLine(to: CGPoint(x: x + 6 * scale, y: y + scale))
            let glimmer = SKShapeNode(path: path)
            glimmer.strokeColor = UIColor(red: 0.78, green: 0.94, blue: 1, alpha: 0.70)
            glimmer.lineWidth = 0.8 * scale
            glimmer.zPosition = 1
            node.addChild(glimmer)
        }
    }

    private static func addCarpetStitching(to node: SKShapeNode, rect: CGRect, scale: CGFloat) {
        for index in 1..<6 {
            let y = rect.minY + rect.height * CGFloat(index) / 6
            let stitch = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.minX + 8 * scale, y: y))
            path.addLine(to: CGPoint(x: rect.maxX - 8 * scale, y: y))
            stitch.path = path
            stitch.strokeColor = UIColor(red: 0.66, green: 0.78, blue: 0.72, alpha: 0.15)
            stitch.lineWidth = 0.65 * scale
            stitch.zPosition = 1
            node.addChild(stitch)
        }
    }

    private static func addLockerVisuals(_ lockers: [LevelLocker], to scene: SKScene, scale: CGFloat) {
        for lockerData in lockers {
            let size = CGSize(width: 28 * scale, height: 38 * scale)
            let rect = CGRect(x: lockerData.center.x - size.width / 2, y: lockerData.center.y - size.height / 2, width: size.width, height: size.height)
            let locker = SKShapeNode(rect: rect, cornerRadius: 3 * scale)
            locker.name = lockerData.id
            locker.fillColor = UIColor(red: 0.085, green: 0.14, blue: 0.16, alpha: 0.96)
            locker.strokeColor = UIColor(red: 0.43, green: 0.58, blue: 0.61, alpha: 0.82)
            locker.lineWidth = 1 * scale
            locker.zPosition = 7
            scene.addChild(locker)

            let seam = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: lockerData.center.x, y: rect.minY + 3 * scale))
            path.addLine(to: CGPoint(x: lockerData.center.x, y: rect.maxY - 3 * scale))
            seam.path = path
            seam.strokeColor = UIColor(white: 0.75, alpha: 0.36)
            seam.lineWidth = 0.7 * scale
            seam.zPosition = 8
            scene.addChild(seam)
        }
    }
}
