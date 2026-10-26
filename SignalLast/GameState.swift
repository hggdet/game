import CoreGraphics
import Foundation

/// The four narrative outcomes. Death is kept separate as a game-over state.
enum GameEnding: String, Codable, CaseIterable, Identifiable, Equatable {
    case earlyEscape
    case stationTruth
    case tragic
    case ambiguous

    var id: String { rawValue }

    var title: String {
        switch self {
        case .earlyEscape: return "نجاة مبكرة"
        case .stationTruth: return "حقيقة المحطة"
        case .tragic: return "النهاية المأساوية"
        case .ambiguous: return "إشارة منقطعة"
        }
    }

    var message: String {
        switch self {
        case .earlyEscape:
            return "غادرت المحطة قبل اكتمال الإشارة. نجوت هذه الليلة، لكن ما حدث في القطاع الشرقي بقي بلا جواب."
        case .stationTruth:
            return "اكتملت الأجزاء الخمسة. كشفت الإشارة أن المحطة كانت ترسل نداء استغاثة منذ سنوات؛ والآن صار بوسع أحدهم سماعك."
        case .tragic:
            return "وصلت إلى الحقيقة، لكن ثمنها كان باهظاً. ما اخترت إنقاذه أو التضحية به سيظل يرافقك بعد مغادرة المحطة."
        case .ambiguous:
            return "انتظرت في الخزانة حتى آخر نبضة. بدأ صوت الإشارة… ثم انقطع، ولم تعرف إن كان أحد قد سمعك."
        }
    }

    var symbol: String {
        switch self {
        case .earlyEscape: return "figure.run"
        case .stationTruth: return "antenna.radiowaves.left.and.right"
        case .tragic: return "heart.slash.fill"
        case .ambiguous: return "waveform.slash"
        }
    }
}

enum PlayerSpeed: String, Equatable {
    case idle
    case sneak
    case walk
    case run

    var arabicTitle: String {
        switch self {
        case .idle: return "ساكن"
        case .sneak: return "تسلّل"
        case .walk: return "مشي"
        case .run: return "ركض"
        }
    }
}

enum DeathAngelState: String, Equatable {
    case dormant
    case patrol
    case investigate
    case chase
    case search

    var arabicTitle: String {
        switch self {
        case .dormant: return "نائم"
        case .patrol: return "دورية"
        case .investigate: return "تحقيق"
        case .chase: return "اندفاع"
        case .search: return "بحث"
        }
    }
}

enum DemogorgonState: String, Equatable {
    case patrol
    case investigate
    case chase
    case search

    var arabicTitle: String {
        switch self {
        case .patrol: return "دورية"
        case .investigate: return "تحقيق الضوء"
        case .chase: return "مطاردة"
        case .search: return "بحث"
        }
    }
}

struct GameState: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var levelLayoutVersion: Int? = nil
    var transmissionInstalled: Bool? = nil
    var transmissionProgress: Double? = nil
    var transmissionCompleted: Bool? = nil
    var hasStarted = false
    var collectedPartIDs: Set<Int> = []
    var points = 0
    var throwItemsRemaining = 3
    var playerXRatio = 0.5
    var playerYRatio = 0.12
    var batteryPercent = 100.0
    var flashlightOn = true
    var flashlightLevel = FlashlightLevel.steady.rawValue
    var savedSurvivor = false
    var sacrificedLight = false
    var escapedEarly = false
    var hidUntilEnd = false
    var usedExit: Bool? = nil
    var openedDoorIDs: Set<String>? = nil
    var isHiding = false
    var isWaitingInHiding = false
    var hideWaitRemaining = 30.0
    var isFinalChoicePending = false
    var ending: GameEnding?
    var didDie = false

    var collectedParts: Int { collectedPartIDs.count }
    var isResumable: Bool { hasStarted && ending == nil && !didDie }
}

enum CheckpointMilestone: String, Codable, CaseIterable, Equatable {
    case afterDoorOne
    case afterPartThree

    var arabicTitle: String {
        switch self {
        case .afterDoorOne: return "بعد الباب الأول"
        case .afterPartThree: return "بعد الجزء الثالث"
        }
    }
}

struct GameCheckpoint: Codable, Equatable {
    var milestone: CheckpointMilestone
    var state: GameState
}

struct AppErrorInfo: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let file: String
    let line: UInt

    var copyText: String {
        "\(message)\n\(file):\(line)"
    }
}

enum GameLoadResult {
    case missing
    case loaded(GameState)
    case corrupted(AppErrorInfo)
}

enum CheckpointLoadResult {
    case missing
    case loaded(GameCheckpoint)
    case corrupted(AppErrorInfo)
}

struct GamePreferences: Codable, Equatable {
    var volume: Double = 0.72
    var hapticsEnabled = true
    var revealMap: Bool? = nil
    var debugEnabled: Bool? = nil

    var normalized: GamePreferences {
        GamePreferences(
            volume: min(max(volume.isFinite ? volume : 0.72, 0), 1),
            hapticsEnabled: hapticsEnabled,
            revealMap: revealMap,
            debugEnabled: debugEnabled
        )
    }
}

enum GameStateStore {
    private static let gameKey = "signal-last.game-state.v1"
    private static let checkpointKey = "signal-last.checkpoint.v1"
    private static let preferencesKey = "signal-last.preferences.v1"

    static func inspectGame(
        defaults: UserDefaults = .standard,
        file: String = #fileID,
        line: UInt = #line
    ) -> GameLoadResult {
        guard let data = defaults.data(forKey: gameKey) else { return .missing }
        do {
            let value = try JSONDecoder().decode(GameState.self, from: data)
            guard value.schemaVersion == GameState.currentSchemaVersion else {
                return .corrupted(AppErrorInfo(
                    message: "نسخة ملف الجولة غير مدعومة (رقم المخطط \(value.schemaVersion)).",
                    file: file,
                    line: line
                ))
            }
            return .loaded(value)
        } catch {
            return .corrupted(AppErrorInfo(
                message: "تعذرت قراءة ملف الجولة المحفوظة: \(error.localizedDescription)",
                file: file,
                line: line
            ))
        }
    }

    static func loadGame(defaults: UserDefaults = .standard) -> GameState? {
        if case .loaded(let state) = inspectGame(defaults: defaults) { return state }
        return nil
    }

    @discardableResult
    static func saveGame(_ state: GameState, defaults: UserDefaults = .standard) -> AppErrorInfo? {
        do {
            let data = try JSONEncoder().encode(state)
            defaults.set(data, forKey: gameKey)
            return nil
        } catch {
            return AppErrorInfo(
                message: "تعذر حفظ الجولة: \(error.localizedDescription)",
                file: #fileID,
                line: #line
            )
        }
    }

    static func clearGame(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: gameKey)
    }

    static func inspectCheckpoint(
        defaults: UserDefaults = .standard,
        file: String = #fileID,
        line: UInt = #line
    ) -> CheckpointLoadResult {
        guard let data = defaults.data(forKey: checkpointKey) else { return .missing }
        do {
            return .loaded(try JSONDecoder().decode(GameCheckpoint.self, from: data))
        } catch {
            return .corrupted(AppErrorInfo(
                message: "تعذرت قراءة نقطة الحفظ: \(error.localizedDescription)",
                file: file,
                line: line
            ))
        }
    }

    static func loadCheckpoint(defaults: UserDefaults = .standard) -> GameCheckpoint? {
        if case .loaded(let checkpoint) = inspectCheckpoint(defaults: defaults) { return checkpoint }
        return nil
    }

    @discardableResult
    static func saveCheckpoint(_ checkpoint: GameCheckpoint, defaults: UserDefaults = .standard) -> AppErrorInfo? {
        do {
            let data = try JSONEncoder().encode(checkpoint)
            defaults.set(data, forKey: checkpointKey)
            return nil
        } catch {
            return AppErrorInfo(
                message: "تعذر حفظ نقطة التحقق: \(error.localizedDescription)",
                file: #fileID,
                line: #line
            )
        }
    }

    static func clearCheckpoint(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: checkpointKey)
    }

    static func loadPreferences(defaults: UserDefaults = .standard) -> GamePreferences {
        guard let data = defaults.data(forKey: preferencesKey),
              let value = try? JSONDecoder().decode(GamePreferences.self, from: data) else {
            return GamePreferences()
        }
        return value.normalized
    }

    static func savePreferences(_ preferences: GamePreferences, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(preferences.normalized) else { return }
        defaults.set(data, forKey: preferencesKey)
    }
}

struct GameSnapshot: Equatable {
    var playerSpeed: PlayerSpeed = .idle
    var deathAngelState: DeathAngelState = .dormant
    var demogorgonState: DemogorgonState = .patrol
    var surface: NoiseSurface = .metal
    var noiseIntensity: CGFloat = 0
    var flashlightLevel: FlashlightLevel = .steady
    var flashlightOn = true
    var batteryPercent: CGFloat = 100
    var pressurePhase: PressurePhase = .calm
    var activeMonster: MonsterKind?
    var threatIntensity: CGFloat = 0
    var flareSecondsRemaining: TimeInterval = 0
    var statusMessage = "حرّك العصا بلطف للتسلل بصمت."

    var collectedParts = 0
    var totalParts = 5
    var points = 0
    var throwItemsRemaining = 3
    var isHiding = false
    var breathMeter: CGFloat = 0
    var isHoldingBreath = false
    var canHide = false
    var canRescueSurvivor = false
    var survivorFollowing = false
    var isFinalChoicePending = false
    var canEscapeEarly = false
    var isWaitingInHiding = false
    var hideWaitRemaining: TimeInterval = 30
    var transmissionInstalled = false
    var transmissionProgress: CGFloat = 0
    var canInstallTransmission = false
    var didFinish = false
    var didLose = false
    var ending: GameEnding?
}
