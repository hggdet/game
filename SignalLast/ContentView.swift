import SwiftUI
import SpriteKit

struct ContentView: View {
    @State private var snapshot = GameSnapshot()
    @State private var joystickValue = CGSize.zero
    @State private var gameScene = GameScene(size: CGSize(width: 390, height: 844))

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SpriteView(scene: gameScene, options: [.ignoresSiblingOrder])
                    .ignoresSafeArea()
                    .accessibilityLabel("غرفة المحطة المهجورة")

                VStack(spacing: 0) {
                    hud
                        .padding(.top, geometry.safeAreaInsets.top + 8)
                    Spacer(minLength: 18)
                    controls
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 10)
                }
                .padding(.horizontal, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .environment(\.layoutDirection, .rightToLeft)
        }
        .preferredColorScheme(.dark)
        .onChange(of: joystickValue) { _, value in
            let limit: CGFloat = 42
            gameScene.setMovementInput(CGVector(dx: value.width / limit, dy: value.height / limit))
        }
        .onAppear {
            gameScene.onSnapshot = { newSnapshot in
                snapshot = newSnapshot
            }
            gameScene.publishSnapshotNow()
        }
    }

    private var hud: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("إشارة أخيرة")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.88, green: 0.95, blue: 0.98))
                    Text("المحطة 09 · القطاع الشرقي")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer(minLength: 4)
                Button {
                    joystickValue = .zero
                    gameScene.setSprintActive(false)
                    gameScene.restart()
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

            HStack(spacing: 8) {
                statusCard(title: "الحركة", value: snapshot.playerSpeed.arabicTitle, symbol: "figure.walk")
                statusCard(title: "Death Angel", value: snapshot.deathAngelState.arabicTitle, symbol: "ear.fill")
                statusCard(title: "الأرض", value: snapshot.surface.arabicTitle, symbol: "square.grid.3x3.fill")
            }

            HStack(spacing: 8) {
                Image(systemName: "waveform.path")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(snapshot.noiseIntensity > 0.55 ? .orange : .cyan)
                ProgressView(value: snapshot.noiseIntensity, total: 1)
                    .tint(snapshot.noiseIntensity > 0.55 ? .orange : .cyan)
                Text("أثر الصوت")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.76))
            }

            Text(snapshot.statusMessage)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(Color(red: 0.025, green: 0.045, blue: 0.061).opacity(0.94))
                .overlay {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .stroke(.white.opacity(0.13), lineWidth: 1)
                }
        }
    }

    private func statusCard(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(.white.opacity(0.53))
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var controls: some View {
        HStack(alignment: .center, spacing: 18) {
            VirtualJoystick { vector in
                let maxRadius: CGFloat = 42
                joystickValue = CGSize(width: vector.dx * maxRadius, height: vector.dy * maxRadius)
            }
            .accessibilityLabel("عصا الحركة الافتراضية")

            Spacer(minLength: 4)

            VStack(spacing: 9) {
                SprintButton { active in
                    gameScene.setSprintActive(active)
                }
                Text("العصا: خفيف = تسلّل · قوي = مشي")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.74))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 156)
                Text("الركض يصدر صوتاً عالياً")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.orange.opacity(0.91))
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
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

private struct VirtualJoystick: View {
    let onChange: (CGVector) -> Void
    @State private var knobOffset = CGSize.zero
    private let diameter: CGFloat = 116
    private let travel: CGFloat = 42

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.07))
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
            Circle()
                .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                .frame(width: diameter * 0.58, height: diameter * 0.58)
            Circle()
                .fill(Color(red: 0.23, green: 0.69, blue: 0.77).opacity(0.80))
                .overlay(Circle().stroke(.white.opacity(0.46), lineWidth: 1))
                .frame(width: 43, height: 43)
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
                    withAnimation(.easeOut(duration: 0.12)) {
                        knobOffset = .zero
                    }
                    onChange(.zero)
                }
        )
    }
}

private struct SprintButton: View {
    let onSprint: (Bool) -> Void
    @State private var pressBeganAt: Date?
    @State private var lastTapAt: Date?
    @State private var holdWorkItem: DispatchWorkItem?
    @State private var isHolding = false
    @State private var isToggled = false

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: isHolding || isToggled ? "figure.run" : "figure.run.circle.fill")
                .font(.system(size: 22, weight: .bold))
            Text(isHolding || isToggled ? "الركض مفعّل" : "ركض")
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .foregroundStyle(isHolding || isToggled ? Color.orange : Color.white.opacity(0.92))
        .frame(width: 126, height: 72)
        .background(isHolding || isToggled ? Color.orange.opacity(0.16) : Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isHolding || isToggled ? Color.orange.opacity(0.52) : Color.white.opacity(0.13), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginPressIfNeeded() }
                .onEnded { _ in endPress() }
        )
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
