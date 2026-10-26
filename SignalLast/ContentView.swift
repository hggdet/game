import SwiftUI
import SpriteKit
import UIKit

struct ContentView: View {
    private enum Screen: Equatable { case menu, game, ending, gameOver, error }
    private enum PendingRun {
        case newGame
        case saved(GameState)
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var screen: Screen = .menu
    @State private var pendingRun: PendingRun?
    @State private var snapshot = GameSnapshot()
    @State private var liveState = GameState()
    @State private var joystickValue = CGSize.zero
    @State private var gameScene = GameScene(size: CGSize(width: 844, height: 390))
    @State private var sprintResetToken = 0
    @State private var volume = GameStateStore.loadPreferences().volume
    @State private var hapticsEnabled = GameStateStore.loadPreferences().hapticsEnabled
    @State private var revealMap = GameStateStore.loadPreferences().revealMap ?? false
    @State private var debugEnabled = GameStateStore.loadPreferences().debugEnabled ?? false
    @State private var appError: AppErrorInfo?

    private var hasContinue: Bool {
        GameStateStore.loadGame()?.isResumable ?? false
    }

    var body: some View {
        Group {
            switch screen {
            case .menu:
                MenuView(
                    hasContinue: hasContinue,
                    volume: $volume,
                    hapticsEnabled: $hapticsEnabled,
                    revealMap: $revealMap,
                    debugEnabled: $debugEnabled,
                    onStart: startNewGame,
                    onContinue: continueGame
                )
            case .game:
                gameBoard
            case .ending:
                if let ending = snapshot.ending ?? liveState.ending {
                    EndingView(ending: ending, state: liveState, onRetry: startNewGame, onMenu: returnToMenu)
                } else {
                    MenuView(hasContinue: hasContinue, volume: $volume, hapticsEnabled: $hapticsEnabled, revealMap: $revealMap, debugEnabled: $debugEnabled, onStart: startNewGame, onContinue: continueGame)
                }
            case .gameOver:
                GameOverView(
                    checkpointTitle: GameStateStore.loadCheckpoint()?.milestone.arabicTitle,
                    onRetry: retryFromCheckpoint,
                    onMenu: returnToMenu
                )
            case .error:
                ErrorView(
                    details: appError ?? AppErrorInfo(message: "حدث خطأ غير متوقع.", file: "ContentView.swift", line: 1),
                    onDismiss: { appError = nil; screen = .menu }
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: screen)
        .preferredColorScheme(.dark)
        .onChange(of: joystickValue) { _, value in
            let limit: CGFloat = 42
            gameScene.setMovementInput(CGVector(dx: value.width / limit, dy: value.height / limit))
        }
        .onChange(of: volume) { _, value in
            var preferences = GameStateStore.loadPreferences()
            preferences.volume = value
            GameStateStore.savePreferences(preferences)
            AudioManager.setVolume(Float(value))
        }
        .onChange(of: hapticsEnabled) { _, value in
            var preferences = GameStateStore.loadPreferences()
            preferences.hapticsEnabled = value
            GameStateStore.savePreferences(preferences)
            gameScene.setHapticsEnabled(value)
        }
        .onChange(of: revealMap) { _, value in
            var preferences = GameStateStore.loadPreferences()
            preferences.revealMap = value
            GameStateStore.savePreferences(preferences)
            gameScene.setRevealMap(value)
        }
        .onChange(of: debugEnabled) { _, value in
            var preferences = GameStateStore.loadPreferences()
            preferences.debugEnabled = value
            GameStateStore.savePreferences(preferences)
            gameScene.setDebugMode(value)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { gameScene.flushProgress() }
        }
        .onAppear {
            configureSceneCallbacks()
            AudioManager.setVolume(Float(volume))
            gameScene.setHapticsEnabled(hapticsEnabled)
            gameScene.setRevealMap(revealMap)
            gameScene.setDebugMode(debugEnabled)
            switch GameStateStore.inspectGame() {
            case .loaded(let saved): liveState = saved
            case .missing: break
            case .corrupted(let details): appError = details; screen = .error
            }
            if appError == nil {
                if case .corrupted(let details) = GameStateStore.inspectCheckpoint() {
                    appError = details
                    screen = .error
                }
            }
            gameScene.publishSnapshotNow()
        }
    }

    private var gameBoard: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let safeInsets = geometry.safeAreaInsets

            ZStack {
                SpriteView(scene: gameScene, options: [.ignoresSiblingOrder])
                    .ignoresSafeArea()
                    .accessibilityLabel("غرفة المحطة المهجورة")

                if isLandscape {
                    VStack(spacing: 7) {
                        landscapeHUD
                        Spacer(minLength: 0)
                        controls(isLandscape: true)
                    }
                    .padding(.leading, max(12, safeInsets.leading + 8))
                    .padding(.trailing, max(12, safeInsets.trailing + 8))
                    .padding(.top, max(8, safeInsets.top + 6))
                    .padding(.bottom, max(8, safeInsets.bottom + 6))
                } else {
                    VStack(spacing: 0) {
                        hud.padding(.top, max(8, safeInsets.top + 8))
                        Spacer(minLength: 12)
                        controls(isLandscape: false)
                            .padding(.bottom, max(8, safeInsets.bottom + 8))
                    }
                    .padding(.horizontal, 14)
                }

                if snapshot.isFinalChoicePending && snapshot.canInstallTransmission {
                    finalChoiceCard
                        .padding(.horizontal, 24)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .environment(\.layoutDirection, .rightToLeft)
        }
        .onAppear {
            configureSceneCallbacks()
            startPendingRunIfNeeded()
        }
    }

    private func configureSceneCallbacks() {
        gameScene.onSnapshot = { newSnapshot in
            guard appError == nil else { return }
            snapshot = newSnapshot
            if newSnapshot.didLose { screen = .gameOver }
            else if newSnapshot.ending != nil { screen = .ending }
            else if screen != .menu { screen = .game }
        }
        gameScene.onProgress = { newState in
            liveState = newState
            if let error = GameStateStore.saveGame(newState) {
                appError = error
                screen = .error
            }
        }
        gameScene.onCheckpoint = { checkpoint in
            if let error = GameStateStore.saveCheckpoint(checkpoint) {
                appError = error
                screen = .error
            }
        }
        gameScene.onDebugModeChanged = { value in
            if debugEnabled != value { debugEnabled = value }
        }
    }

    private func startNewGame() {
        let isAlreadyInGame = screen == .game
        joystickValue = .zero
        sprintResetToken += 1
        snapshot = GameSnapshot()
        liveState = GameState()
        GameStateStore.clearGame()
        GameStateStore.clearCheckpoint()
        appError = nil
        pendingRun = .newGame
        screen = .game
        if isAlreadyInGame { startPendingRunIfNeeded() }
    }

    private func continueGame() {
        guard let saved = GameStateStore.loadGame(), saved.isResumable else { return }
        joystickValue = .zero
        sprintResetToken += 1
        liveState = saved
        pendingRun = .saved(saved)
        screen = .game
    }

    private func retryFromCheckpoint() {
        guard let checkpoint = GameStateStore.loadCheckpoint() else {
            startNewGame()
            return
        }
        joystickValue = .zero
        sprintResetToken += 1
        snapshot = GameSnapshot()
        liveState = checkpoint.state
        pendingRun = .saved(checkpoint.state)
        screen = .game
    }

    private func startPendingRunIfNeeded() {
        guard let pendingRun else { return }
        self.pendingRun = nil
        DispatchQueue.main.async {
            guard screen == .game else { return }
            configureSceneCallbacks()
            switch pendingRun {
            case .newGame:
                gameScene.startNewGame()
            case .saved(let saved):
                gameScene.loadGame(saved)
            }
        }
    }

    private func returnToMenu() {
        gameScene.flushProgress()
        joystickValue = .zero
        screen = .menu
    }

    private var hud: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("إشارة أخيرة")
                        .font(.system(size: 21, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.88, green: 0.95, blue: 0.98))
                    Text("المحطة 09 · القطاع الشرقي")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer(minLength: 4)
                Button(action: returnToMenu) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.84))
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("القائمة الرئيسية")
                Button {
                    startNewGame()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.84))
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("إعادة اللعب")
            }

            HStack(spacing: 7) {
                statusCard(title: "الحركة", value: snapshot.playerSpeed.arabicTitle, symbol: "figure.walk")
                statusCard(title: "Death Angel", value: snapshot.deathAngelState.arabicTitle, symbol: "ear.fill")
                statusCard(title: "Demogorgon", value: snapshot.demogorgonState.arabicTitle, symbol: "eye.fill")
            }

            HStack(spacing: 9) {
                Image(systemName: "waveform.path")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(snapshot.noiseIntensity > 0.55 ? .orange : .cyan)
                ProgressView(value: snapshot.noiseIntensity, total: 1)
                    .tint(snapshot.noiseIntensity > 0.55 ? .orange : .cyan)
                Text("الصوت")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
                Text(snapshot.pressurePhase.arabicTitle)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(pressureColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(pressureColor.opacity(0.13), in: Capsule())
            }

            HStack(spacing: 8) {
                Label("الأجزاء \(snapshot.collectedParts)/\(snapshot.totalParts)", systemImage: "diamond.fill")
                    .foregroundStyle(.cyan)
                Spacer(minLength: 2)
                Text("النقاط \(snapshot.points)")
                    .foregroundStyle(.white.opacity(0.86))
                Spacer(minLength: 2)
                Label("رميات \(snapshot.throwItemsRemaining)", systemImage: "circle.grid.cross.fill")
                    .foregroundStyle(snapshot.throwItemsRemaining > 0 ? .white.opacity(0.86) : .orange)
            }
            .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())

            HStack(spacing: 8) {
                Image(systemName: snapshot.isHoldingBreath ? "lungs.fill" : "wind")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(snapshot.breathMeter > 0.72 ? .orange : .cyan)
                ProgressView(value: min(max(snapshot.breathMeter, 0), 1), total: 1)
                    .tint(snapshot.breathMeter > 0.72 ? .orange : .cyan)
                Text(snapshot.isHiding ? (snapshot.isHoldingBreath ? "كتم النفس" : "النفس مكشوف") : "النفس")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("مقياس ضغط النفس \(Int(snapshot.breathMeter * 100)) بالمئة")

            HStack(spacing: 8) {
                Image(systemName: snapshot.flashlightOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(snapshot.batteryPercent < 20 ? .orange : .yellow)
                ProgressView(value: snapshot.batteryPercent, total: 100)
                    .tint(snapshot.batteryPercent < 20 ? .orange : .yellow)
                Text("\(Int(snapshot.batteryPercent.rounded()))٪")
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(minWidth: 34, alignment: .trailing)
                Text(snapshot.flashlightLevel.arabicTitle)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.70))
            }

            HStack(spacing: 5) {
                Text(snapshot.statusMessage)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if snapshot.flareSecondsRemaining > 0 {
                    Label("\(Int(snapshot.flareSecondsRemaining))ث", systemImage: "flame.fill")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                        .fixedSize()
                }
            }
            if snapshot.transmissionInstalled {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(.cyan)
                    ProgressView(value: snapshot.transmissionProgress, total: 1).tint(.cyan)
                    Text("الإرسال \(Int((snapshot.transmissionProgress * 10).rounded()))/10ث")
                        .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.9))
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(Color(red: 0.025, green: 0.045, blue: 0.061).opacity(0.94))
                .overlay {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .stroke(.white.opacity(0.13), lineWidth: 1)
                }
        }
    }

    private var finalChoiceCard: some View {
        VStack(spacing: 13) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.cyan)
            Text("الأجزاء الخمسة جاهزة للإرسال")
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("ركّب الجهاز هنا. يلزم ضوء قوي وضوضاء عالية معاً لعشر ثوانٍ؛ سيهاجم الوحشان. يمكنك أيضاً العودة إلى المخرج.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.79))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            decisionButton("ركّب جهاز الإرسال", symbol: "waveform", tint: .cyan) {
                gameScene.chooseStationTruth()
            }
            decisionButton("ضحِّ بالمصباح", symbol: "flashlight.off.fill", tint: .orange) {
                gameScene.chooseSacrificeLight()
            }
            Text("إن أنقذت الناجي، تتغير النهاية تلقائياً.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.025, green: 0.045, blue: 0.061).opacity(0.98))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.cyan.opacity(0.38), lineWidth: 1))
        }
        .shadow(color: .black.opacity(0.5), radius: 22, y: 9)
    }

    private func decisionButton(_ title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                Text(title).font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(tint.opacity(0.34), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var pressureColor: Color {
        switch snapshot.pressurePhase {
        case .calm: return .cyan
        case .buildUp: return .yellow
        case .attack: return .red
        case .retreat: return .green
        }
    }

    private func statusCard(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                Text(title).font(.system(size: 8, weight: .medium, design: .rounded)).lineLimit(1).minimumScaleFactor(0.72)
            }
            .foregroundStyle(.white.opacity(0.53))
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var landscapeHUD: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("إشارة أخيرة")
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.88, green: 0.95, blue: 0.98))
                    Text("المحطة 09 · القطاع الشرقي")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.58))
                }
                .fixedSize(horizontal: true, vertical: false)

                HStack(spacing: 6) {
                    statusCard(title: "الحركة", value: snapshot.playerSpeed.arabicTitle, symbol: "figure.walk")
                    statusCard(title: "Death Angel", value: snapshot.deathAngelState.arabicTitle, symbol: "ear.fill")
                    statusCard(title: "Demogorgon", value: snapshot.demogorgonState.arabicTitle, symbol: "eye.fill")
                }
                .frame(maxWidth: 370)

                Spacer(minLength: 2)

                Button(action: returnToMenu) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.84))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("القائمة الرئيسية")

                Button(action: startNewGame) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.84))
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("إعادة اللعب")
            }

            HStack(spacing: 10) {
                landscapeMeter(title: "الصوت", value: snapshot.noiseIntensity, symbol: "waveform.path", tint: snapshot.noiseIntensity > 0.55 ? .orange : .cyan)
                landscapeMeter(title: "النفس", value: snapshot.breathMeter, symbol: snapshot.isHoldingBreath ? "lungs.fill" : "wind", tint: snapshot.breathMeter > 0.72 ? .orange : .cyan)
                HStack(spacing: 5) {
                    Image(systemName: snapshot.flashlightOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .foregroundStyle(snapshot.batteryPercent < 20 ? .orange : .yellow)
                    Text("\(Int(snapshot.batteryPercent.rounded()))٪")
                        .foregroundStyle(.white.opacity(0.88))
                    ProgressView(value: snapshot.batteryPercent, total: 100)
                        .tint(snapshot.batteryPercent < 20 ? .orange : .yellow)
                        .frame(width: 64)
                }
                .font(.system(size: 8, weight: .bold, design: .rounded).monospacedDigit())

                Label("\(snapshot.collectedParts)/\(snapshot.totalParts)", systemImage: "diamond.fill")
                    .foregroundStyle(.cyan)
                Text("النقاط \(snapshot.points)")
                    .foregroundStyle(.white.opacity(0.86))
                Label("\(snapshot.throwItemsRemaining)", systemImage: "circle.grid.cross.fill")
                    .foregroundStyle(snapshot.throwItemsRemaining > 0 ? .white.opacity(0.86) : .orange)

                if snapshot.transmissionInstalled {
                    HStack(spacing: 4) {
                        Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(.cyan)
                        ProgressView(value: snapshot.transmissionProgress, total: 1).tint(.cyan).frame(width: 58)
                        Text("\(Int((snapshot.transmissionProgress * 10).rounded()))ث")
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }

                Text(snapshot.statusMessage)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 8, weight: .bold, design: .rounded).monospacedDigit())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Color(red: 0.025, green: 0.045, blue: 0.061).opacity(0.94))
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(.white.opacity(0.13), lineWidth: 1)
                }
        }
    }

    private func landscapeMeter(title: String, value: CGFloat, symbol: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(title).foregroundStyle(.white.opacity(0.72))
            ProgressView(value: min(max(value, 0), 1), total: 1)
                .tint(tint)
                .frame(width: 52)
        }
    }

    private func controls(isLandscape: Bool) -> some View {
        HStack(alignment: .center, spacing: isLandscape ? 7 : 9) {
            VirtualJoystick { vector in
                let maxRadius: CGFloat = 42
                joystickValue = CGSize(width: vector.dx * maxRadius, height: vector.dy * maxRadius)
            }
            Spacer(minLength: 0)
            VStack(spacing: isLandscape ? 4 : 7) {
                HStack(spacing: 6) {
                    ControlActionButton(title: snapshot.flashlightOn ? "إطفاء" : "مصباح", symbol: snapshot.flashlightOn ? "flashlight.off.fill" : "flashlight.on.fill", tint: .yellow, compact: isLandscape) {
                        gameScene.toggleFlashlight()
                    }
                    ControlActionButton(title: "المستوى", symbol: "circle.lefthalf.filled", tint: .cyan, compact: isLandscape) {
                        gameScene.cycleFlashlightLevel()
                    }
                }
                HStack(spacing: 6) {
                    ControlActionButton(title: "فلير", symbol: "flame.fill", tint: .orange, compact: isLandscape) {
                        gameScene.placeFlare()
                    }
                    ControlActionButton(title: "رمي \(snapshot.throwItemsRemaining)", symbol: "arrow.up.forward", tint: .white, enabled: snapshot.throwItemsRemaining > 0 && !snapshot.didFinish, compact: isLandscape) {
                        gameScene.throwNoiseItem()
                    }
                }
                HStack(spacing: 6) {
                    ControlActionButton(title: snapshot.isHiding ? "خروج" : "اختباء", symbol: snapshot.isHiding ? "door.left.hand.open" : "cabinet.fill", tint: .cyan, enabled: snapshot.canHide && !snapshot.didFinish, compact: isLandscape) {
                        gameScene.toggleHiding()
                    }
                    ControlActionButton(title: snapshot.survivorFollowing ? "يتبعك" : "إنقاذ", symbol: snapshot.survivorFollowing ? "figure.2" : "figure.2.and.child.holdinghands", tint: .orange, enabled: snapshot.canRescueSurvivor && !snapshot.didFinish, compact: isLandscape) {
                        gameScene.rescueSurvivor()
                    }
                }
                if snapshot.isHiding {
                    ControlActionButton(
                        title: snapshot.isWaitingInHiding ? "انتظر \(Int(ceil(snapshot.hideWaitRemaining)))ث" : "انتظر النهاية",
                        symbol: "waveform.slash",
                        tint: .purple,
                        enabled: !snapshot.isWaitingInHiding && !snapshot.didFinish,
                        compact: isLandscape
                    ) {
                        gameScene.waitInHidingUntilSignalFades()
                    }
                } else if snapshot.canEscapeEarly {
                    ControlActionButton(title: "اهرب الآن", symbol: "door.left.hand.open", tint: .green, enabled: !snapshot.didFinish, compact: isLandscape) {
                        gameScene.escapeEarly()
                    }
                }
                HoldBreathButton(isHiding: snapshot.isHiding, isHolding: snapshot.isHoldingBreath, compact: isLandscape) { active in
                    gameScene.setHoldingBreath(active)
                }
                .frame(width: 152)
                SprintButton(compact: isLandscape) { active in gameScene.setSprintActive(active) }
                    .id(sprintResetToken)
                if !isLandscape {
                    Text("الركض والناجي يصدران صوتاً · المصباح يجذب Demogorgon")
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.70))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 166)
                }
            }
        }
        .padding(.horizontal, isLandscape ? 8 : 10)
        .padding(.vertical, isLandscape ? 6 : 10)
        .frame(maxWidth: .infinity)
        .environment(\.layoutDirection, .leftToRight)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(red: 0.025, green: 0.045, blue: 0.061).opacity(0.94))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
        }
    }
}

private struct ControlActionButton: View {
    let title: String
    let symbol: String
    let tint: Color
    var enabled = true
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: compact ? 11 : 13, weight: .bold))
                Text(title).font(.system(size: compact ? 7 : 8, weight: .bold, design: .rounded)).lineLimit(1)
            }
            .foregroundStyle(tint)
            .frame(width: compact ? 68 : 73, height: compact ? 30 : 36)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.42)
    }
}

private struct HoldBreathButton: View {
    let isHiding: Bool
    let isHolding: Bool
    var compact = false
    let onHold: (Bool) -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: isHolding ? "lungs.fill" : "wind")
                .font(.system(size: compact ? 12 : 14, weight: .bold))
            Text(isHolding ? "تحبس أنفاسك…" : "اضغط مطولاً لكتم النفس")
                .font(.system(size: compact ? 8 : 9, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isHolding ? Color.cyan : Color.white.opacity(0.85))
        .frame(height: compact ? 29 : 34)
        .frame(maxWidth: .infinity)
        .background(isHolding ? Color.cyan.opacity(0.16) : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(isHolding ? Color.cyan.opacity(0.5) : Color.white.opacity(0.12), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onHold(true) }
                .onEnded { _ in onHold(false) }
        )
        .disabled(!isHiding)
        .opacity(isHiding ? 1 : 0.42)
        .onDisappear { onHold(false) }
        .accessibilityLabel(isHiding ? "اضغط مطولاً لحبس النفس" : "ادخل خزانة لاستخدام كتم النفس")
    }
}

private struct VirtualJoystick: View {
    let onChange: (CGVector) -> Void
    @State private var knobOffset = CGSize.zero
    private let diameter: CGFloat = 105
    private let travel: CGFloat = 42

    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.07)).overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
            Circle().stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 5])).frame(width: diameter * 0.58, height: diameter * 0.58)
            Circle()
                .fill(Color(red: 0.23, green: 0.69, blue: 0.77).opacity(0.80))
                .overlay(Circle().stroke(.white.opacity(0.46), lineWidth: 1))
                .frame(width: 41, height: 41)
                .shadow(color: .cyan.opacity(0.22), radius: 8)
                .offset(knobOffset)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let translation = value.translation
                    let length = sqrt(translation.width * translation.width + translation.height * translation.height)
                    let factor = length > travel ? travel / length : 1
                    let offset = CGSize(width: translation.width * factor, height: translation.height * factor)
                    knobOffset = offset
                    onChange(CGVector(dx: offset.width / travel, dy: -offset.height / travel))
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.12)) { knobOffset = .zero }
                    onChange(.zero)
                }
        )
        .accessibilityLabel("عصا الحركة الافتراضية")
    }
}

private struct SprintButton: View {
    var compact = false
    let onSprint: (Bool) -> Void
    @State private var pressBeganAt: Date?
    @State private var lastTapAt: Date?
    @State private var holdWorkItem: DispatchWorkItem?
    @State private var isHolding = false
    @State private var isToggled = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: isHolding || isToggled ? "figure.run" : "figure.run.circle.fill")
                .font(.system(size: compact ? 14 : 17, weight: .bold))
            Text(isHolding || isToggled ? "الركض مفعّل" : "ركض")
                .font(.system(size: compact ? 9 : 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(isHolding || isToggled ? Color.orange : Color.white.opacity(0.92))
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 32 : 40)
        .background(isHolding || isToggled ? Color.orange.opacity(0.16) : Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isHolding || isToggled ? Color.orange.opacity(0.52) : Color.white.opacity(0.13), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginPressIfNeeded() }
                .onEnded { _ in endPress() }
        )
        .onDisappear {
            holdWorkItem?.cancel()
            holdWorkItem = nil
            onSprint(false)
        }
        .accessibilityLabel("زر الركض: اضغط مطولاً أو انقر مرتين للتبديل")
    }

    private func beginPressIfNeeded() {
        guard pressBeganAt == nil else { return }
        pressBeganAt = Date()
        let work = DispatchWorkItem {
            guard pressBeganAt != nil else { return }
            isHolding = true
            onSprint(true)
        }
        holdWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func endPress() {
        holdWorkItem?.cancel()
        holdWorkItem = nil
        if isHolding {
            isHolding = false
            onSprint(isToggled)
            pressBeganAt = nil
            return
        }
        let now = Date()
        if let previousTap = lastTapAt, now.timeIntervalSince(previousTap) <= 0.34 {
            isToggled.toggle()
            onSprint(isToggled)
            lastTapAt = nil
        } else {
            lastTapAt = now
        }
        pressBeganAt = nil
    }
}
