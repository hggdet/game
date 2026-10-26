import Foundation

enum MonsterKind: String, Equatable {
    case deathAngel
    case demogorgon

    var arabicTitle: String {
        switch self {
        case .deathAngel: return "Death Angel"
        case .demogorgon: return "Demogorgon"
        }
    }
}

enum PressurePhase: String, Equatable {
    case calm
    case buildUp
    case attack
    case retreat

    var arabicTitle: String {
        switch self {
        case .calm: return "هدوء"
        case .buildUp: return "تصاعد"
        case .attack: return "هجوم"
        case .retreat: return "انسحاب"
        }
    }
}

/// Keeps the hunters off-screen between pressure cycles. The final 2.5 seconds
/// of every build-up are intentionally silent before the attacker enters.
final class MonsterDirector {
    private(set) var phase: PressurePhase = .calm
    private(set) var activeMonster: MonsterKind?
    var onPhaseChange: ((PressurePhase) -> Void)?
    var onBuildUpSound: ((Bool) -> Void)?
    var onAttack: ((MonsterKind) -> Void)?
    var onRetreat: (() -> Void)?

    private var elapsed: TimeInterval = 0
    private var nextMonster: MonsterKind = .demogorgon
    private var preferredMonster: MonsterKind?
    private var playedSecondBuildSound = false

    func advance(delta: TimeInterval) {
        guard delta > 0 else { return }
        elapsed += delta

        switch phase {
        case .calm:
            if elapsed >= 13 {
                beginBuildUp()
            }
        case .buildUp:
            if !playedSecondBuildSound && elapsed >= 2.7 {
                playedSecondBuildSound = true
                onBuildUpSound?(true)
            }
            // The last sound is at 2.7s; wait a full 2.5s before attack.
            if elapsed >= 5.2 {
                beginAttack()
            }
        case .attack:
            if elapsed >= 10.5 {
                activeMonster = nil
                onRetreat?()
                setPhase(.retreat)
            }
        case .retreat:
            if elapsed >= 4.5 {
                preferredMonster = nil
                setPhase(.calm)
            }
        }
    }

    /// A loud impact, especially a thrown object against a sealed door, wakes
    /// the sound hunter and starts an early pressure cycle.
    func wakeDeathAngel() {
        guard !(phase == .attack && activeMonster == .deathAngel) else { return }
        preferredMonster = .deathAngel
        if phase == .buildUp { return }
        if phase == .attack {
            activeMonster = nil
            onRetreat?()
        }
        // Even if another creature was attacking, re-enter build-up so the
        // Death Angel still receives the required silent warning interval.
        beginBuildUp()
    }

    func notifyLoudNoise() {
        guard phase == .calm else { return }
        preferredMonster = .deathAngel
        beginBuildUp()
    }

    private func beginBuildUp() {
        elapsed = 0
        playedSecondBuildSound = false
        setPhase(.buildUp)
        onBuildUpSound?(false)
    }

    private func beginAttack() {
        let monster = preferredMonster ?? nextMonster
        activeMonster = monster
        nextMonster = monster == .demogorgon ? .deathAngel : .demogorgon
        elapsed = 0
        setPhase(.attack)
        onAttack?(monster)
    }

    private func setPhase(_ newPhase: PressurePhase) {
        guard phase != newPhase else { return }
        phase = newPhase
        elapsed = 0
        onPhaseChange?(newPhase)
    }
}
