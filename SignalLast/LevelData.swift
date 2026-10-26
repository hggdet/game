import CoreGraphics
import Foundation

struct StationLevelData {
    let worldBounds: CGRect
    let rooms: [LevelRoom]
    let doors: [LevelDoorLayout]
    let pickups: [LevelPickup]
    let lockers: [LevelLocker]
    let spawns: LevelSpawnPoints
    let demogorgonPatrolWaypoints: [CGPoint]
    let deathAngelPatrolWaypoints: [CGPoint]
    let surfaceZones: [SurfaceZoneLayout]
    let wallRects: [CGRect]

    func room(id: String) -> LevelRoom? {
        rooms.first { $0.id == id }
    }

    func surfaceZone(id: String) -> SurfaceZoneLayout? {
        surfaceZones.first { $0.id == id }
    }

    func scaled(by factor: CGFloat) -> StationLevelData {
        StationLevelData(
            worldBounds: worldBounds.scaled(by: factor),
            rooms: rooms.map { $0.scaled(by: factor) },
            doors: doors.map { $0.scaled(by: factor) },
            pickups: pickups.map { $0.scaled(by: factor) },
            lockers: lockers.map { $0.scaled(by: factor) },
            spawns: spawns.scaled(by: factor),
            demogorgonPatrolWaypoints: demogorgonPatrolWaypoints.map { $0.scaled(by: factor) },
            deathAngelPatrolWaypoints: deathAngelPatrolWaypoints.map { $0.scaled(by: factor) },
            surfaceZones: surfaceZones.map { $0.scaled(by: factor) },
            wallRects: wallRects.map { $0.scaled(by: factor) }
        )
    }

    static let standard = StationLevelData(
        worldBounds: CGRect(x: 0, y: 0, width: 3000, height: 1200),
        rooms: [
            LevelRoom(id: "entrance", title: "مدخل المحطة", rect: CGRect(x: 70, y: 370, width: 610, height: 480)),
            LevelRoom(id: "entrance-side-room", title: "المخزن الجانبي", rect: CGRect(x: 330, y: 115, width: 300, height: 245)),
            LevelRoom(id: "entry-corridor", title: "الممر الأول", rect: CGRect(x: 680, y: 510, width: 380, height: 148)),
            LevelRoom(id: "lab-a", title: "المختبر أ", rect: CGRect(x: 790, y: 650, width: 520, height: 390)),
            LevelRoom(id: "lab-b", title: "المختبر ب", rect: CGRect(x: 1310, y: 650, width: 540, height: 390)),
            LevelRoom(id: "survivor-room", title: "غرفة الناجي", rect: CGRect(x: 1430, y: 350, width: 290, height: 250)),
            LevelRoom(id: "storage", title: "مستودع المعدات", rect: CGRect(x: 1880, y: 350, width: 490, height: 470)),
            LevelRoom(id: "metal-corridor", title: "الممر المعدني", rect: CGRect(x: 2370, y: 515, width: 340, height: 130)),
            LevelRoom(id: "transmission-room", title: "غرفة الإرسال", rect: CGRect(x: 2710, y: 365, width: 250, height: 440))
        ],
        doors: [
            LevelDoorLayout(id: "door-1", rect: CGRect(x: 704, y: 518, width: 18, height: 132), title: "الباب المختوم ١", isInitiallyOpen: false),
            LevelDoorLayout(id: "survivor-door", rect: CGRect(x: 1510, y: 588, width: 130, height: 12), title: "غرفة الناجي · مقفلة", isInitiallyOpen: false)
        ],
        pickups: [
            LevelPickup(id: 1, position: CGPoint(x: 590, y: 150), isNoisy: false, title: "القطعة ١"),
            LevelPickup(id: 2, position: CGPoint(x: 970, y: 820), isNoisy: false, title: "القطعة ٢"),
            LevelPickup(id: 3, position: CGPoint(x: 1630, y: 835), isNoisy: true, title: "بطارية معدنية · صاخبة"),
            LevelPickup(id: 4, position: CGPoint(x: 2300, y: 405), isNoisy: false, title: "القطعة ٤"),
            LevelPickup(id: 5, position: CGPoint(x: 2525, y: 580), isNoisy: true, title: "القطعة ٥")
        ],
        lockers: [
            LevelLocker(id: "locker-lab-b-1", center: CGPoint(x: 1445, y: 720)),
            LevelLocker(id: "locker-lab-b-2", center: CGPoint(x: 1760, y: 900)),
            LevelLocker(id: "locker-metal-corridor", center: CGPoint(x: 2600, y: 580))
        ],
        spawns: LevelSpawnPoints(
            player: CGPoint(x: 145, y: 610),
            deathAngel: CGPoint(x: 2180, y: 580),
            demogorgon: CGPoint(x: 1030, y: 830),
            survivor: CGPoint(x: 1550, y: 470),
            transmission: CGPoint(x: 2835, y: 585)
        ),
        demogorgonPatrolWaypoints: [
            CGPoint(x: 980, y: 790), CGPoint(x: 1170, y: 930), CGPoint(x: 1260, y: 830),
            CGPoint(x: 1380, y: 830), CGPoint(x: 1650, y: 920), CGPoint(x: 1760, y: 730), CGPoint(x: 1430, y: 700), CGPoint(x: 990, y: 700)
        ],
        deathAngelPatrolWaypoints: [
            CGPoint(x: 2440, y: 580), CGPoint(x: 2560, y: 580), CGPoint(x: 2660, y: 580), CGPoint(x: 2510, y: 560)
        ],
        surfaceZones: [
            SurfaceZoneLayout(id: "entrance-carpet", rect: CGRect(x: 680, y: 522, width: 112, height: 124), surface: .carpet, title: "سجاد · هادئ"),
            SurfaceZoneLayout(id: "broken-glass", rect: CGRect(x: 2180, y: 365, width: 165, height: 170), surface: .glass, title: "زجاج مكسور · خطر"),
            SurfaceZoneLayout(id: "metal-corridor-surface", rect: CGRect(x: 2370, y: 515, width: 340, height: 130), surface: .metal, title: "ممر معدني · صاخب")
        ],
        wallRects: [
            // Outer entrance walls.
            CGRect(x: 70, y: 362, width: 360, height: 12),
            CGRect(x: 530, y: 362, width: 150, height: 12),
            CGRect(x: 70, y: 850, width: 610, height: 12),
            CGRect(x: 58, y: 370, width: 12, height: 480),
            CGRect(x: 680, y: 370, width: 12, height: 148),
            CGRect(x: 680, y: 650, width: 12, height: 200),
            // Side nook perimeter, with a deliberate south opening into its vestibule.
            CGRect(x: 330, y: 103, width: 300, height: 12),
            CGRect(x: 318, y: 115, width: 12, height: 245),
            CGRect(x: 630, y: 115, width: 12, height: 245),
            CGRect(x: 330, y: 348, width: 100, height: 12),
            CGRect(x: 530, y: 348, width: 100, height: 12),
            // Zone threshold. Door 1 seals the entrance; a separate door seals the survivor room.
            CGRect(x: 722, y: 510, width: 12, height: 8),
            CGRect(x: 722, y: 650, width: 12, height: 8),
            CGRect(x: 734, y: 510, width: 56, height: 12),
            CGRect(x: 734, y: 646, width: 56, height: 12),
            // Lab A and its open eastern connection into Lab B.
            CGRect(x: 790, y: 638, width: 150, height: 12),
            CGRect(x: 1060, y: 638, width: 250, height: 12),
            CGRect(x: 790, y: 1040, width: 520, height: 12),
            CGRect(x: 778, y: 650, width: 12, height: 390),
            CGRect(x: 1310, y: 650, width: 12, height: 100),
            CGRect(x: 1310, y: 920, width: 12, height: 120),
            // Lab B, with a northward-free passage to the survivor room.
            CGRect(x: 1322, y: 638, width: 108, height: 12),
            CGRect(x: 1720, y: 638, width: 130, height: 12),
            CGRect(x: 1310, y: 1040, width: 540, height: 12),
            CGRect(x: 1850, y: 650, width: 12, height: 110),
            CGRect(x: 1850, y: 820, width: 12, height: 220),
            // Survivor room perimeter; its north opening aligns with Lab B.
            CGRect(x: 1430, y: 338, width: 290, height: 12),
            CGRect(x: 1418, y: 350, width: 12, height: 250),
            CGRect(x: 1720, y: 350, width: 12, height: 250),
            CGRect(x: 1430, y: 588, width: 80, height: 12),
            CGRect(x: 1640, y: 588, width: 80, height: 12),
            // Storage connections west to Lab B and east to the metal corridor.
            CGRect(x: 1880, y: 338, width: 490, height: 12),
            CGRect(x: 1868, y: 350, width: 12, height: 410),
            CGRect(x: 2370, y: 350, width: 12, height: 165),
            CGRect(x: 2370, y: 645, width: 12, height: 175),
            CGRect(x: 1880, y: 820, width: 490, height: 12),
            // Narrow metal corridor to the transmission room.
            CGRect(x: 2370, y: 503, width: 340, height: 12),
            CGRect(x: 2370, y: 645, width: 340, height: 12),
            // Transmission room entrance remains open from the corridor.
            CGRect(x: 2710, y: 353, width: 250, height: 12),
            CGRect(x: 2710, y: 805, width: 250, height: 12),
            CGRect(x: 2698, y: 365, width: 12, height: 150),
            CGRect(x: 2698, y: 645, width: 12, height: 160),
            CGRect(x: 2960, y: 365, width: 12, height: 440),
            // Lab equipment partitions; neither intersects the through-route.
            CGRect(x: 1080, y: 700, width: 10, height: 70),
            CGRect(x: 1080, y: 900, width: 10, height: 100),
            CGRect(x: 1785, y: 700, width: 10, height: 120)
        ]
    )
}

struct LevelRoom {
    let id: String
    let title: String
    let rect: CGRect

    func scaled(by factor: CGFloat) -> LevelRoom {
        LevelRoom(id: id, title: title, rect: rect.scaled(by: factor))
    }
}

struct LevelDoorLayout {
    let id: String
    let rect: CGRect
    let title: String
    let isInitiallyOpen: Bool

    func scaled(by factor: CGFloat) -> LevelDoorLayout {
        LevelDoorLayout(id: id, rect: rect.scaled(by: factor), title: title, isInitiallyOpen: isInitiallyOpen)
    }
}

struct LevelPickup {
    let id: Int
    let position: CGPoint
    let isNoisy: Bool
    let title: String

    func scaled(by factor: CGFloat) -> LevelPickup {
        LevelPickup(id: id, position: position.scaled(by: factor), isNoisy: isNoisy, title: title)
    }
}

struct LevelLocker {
    let id: String
    let center: CGPoint

    func scaled(by factor: CGFloat) -> LevelLocker {
        LevelLocker(id: id, center: center.scaled(by: factor))
    }
}

struct LevelSpawnPoints {
    let player: CGPoint
    let deathAngel: CGPoint
    let demogorgon: CGPoint
    let survivor: CGPoint
    let transmission: CGPoint

    func scaled(by factor: CGFloat) -> LevelSpawnPoints {
        LevelSpawnPoints(
            player: player.scaled(by: factor),
            deathAngel: deathAngel.scaled(by: factor),
            demogorgon: demogorgon.scaled(by: factor),
            survivor: survivor.scaled(by: factor),
            transmission: transmission.scaled(by: factor)
        )
    }
}

struct SurfaceZoneLayout {
    let id: String
    let rect: CGRect
    let surface: NoiseSurface
    let title: String

    func scaled(by factor: CGFloat) -> SurfaceZoneLayout {
        SurfaceZoneLayout(id: id, rect: rect.scaled(by: factor), surface: surface, title: title)
    }
}

private extension CGPoint {
    func scaled(by factor: CGFloat) -> CGPoint {
        CGPoint(x: x * factor, y: y * factor)
    }
}

private extension CGRect {
    func scaled(by factor: CGFloat) -> CGRect {
        CGRect(x: origin.x * factor, y: origin.y * factor, width: size.width * factor, height: size.height * factor)
    }
}
