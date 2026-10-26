import SwiftUI

struct MenuView: View {
    let hasContinue: Bool
    @Binding var volume: Double
    @Binding var hapticsEnabled: Bool
    let onStart: () -> Void
    let onContinue: () -> Void

    @State private var showingSettings = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.015, green: 0.045, blue: 0.065), .black, Color(red: 0.045, green: 0.018, blue: 0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.cyan.opacity(0.10))
                .frame(width: 260, height: 260)
                .blur(radius: 80)
                .offset(x: 100, y: -190)
            Circle()
                .fill(Color.red.opacity(0.08))
                .frame(width: 280, height: 280)
                .blur(radius: 85)
                .offset(x: -120, y: 250)

            VStack(spacing: 0) {
                Spacer(minLength: 38)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(Color.cyan.opacity(0.92))
                    .padding(.bottom, 22)
                    .shadow(color: .cyan.opacity(0.4), radius: 22)

                Text("إشارة أخيرة")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("المحطة 09 · القطاع الشرقي")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.52))
                    .padding(.top, 9)
                Text("اجمع شظايا الإشارة. لا تدع الضوء أو الصوت يكشفانك.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.76))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.top, 28)

                Spacer(minLength: 36)
                VStack(spacing: 12) {
                    menuButton("ابدأ لعبة جديدة", symbol: "play.fill", prominent: true, action: onStart)
                    menuButton("متابعة الجولة", symbol: "arrow.uturn.forward", prominent: false, action: onContinue)
                        .disabled(!hasContinue)
                        .opacity(hasContinue ? 1 : 0.42)
                    menuButton("الإعدادات", symbol: "slider.horizontal.3", prominent: false) {
                        showingSettings = true
                    }
                }
                .padding(.horizontal, 30)
                Spacer(minLength: 42)
                Text("تجربة رعب فردية · iOS 17+")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.34))
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: 520)
        }
        .environment(\.layoutDirection, .rightToLeft)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingSettings) {
            settingsSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("الصوت") {
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.cyan)
                        Slider(value: $volume, in: 0...1, step: 0.01)
                            .tint(.cyan)
                        Text("\(Int((volume * 100).rounded()))٪")
                            .font(.system(.caption, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .leading)
                    }
                    Text("يضبط مستوى المؤثرات الصوتية المكانية.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("الاهتزاز") {
                    Toggle(isOn: $hapticsEnabled) {
                        Label("نبضات الخطر اللمسية", systemImage: "waveform.path")
                    }
                    .tint(.cyan)
                }
            }
            .navigationTitle("الإعدادات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { showingSettings = false }
                        .tint(.cyan)
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .preferredColorScheme(.dark)
        }
    }

    private func menuButton(_ title: String, symbol: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .bold))
                    .opacity(0.62)
            }
            .foregroundStyle(prominent ? Color.black : Color.white.opacity(0.93))
            .padding(.horizontal, 18)
            .frame(height: 56)
            .background {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(prominent ? Color.cyan : Color.white.opacity(0.075))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(prominent ? Color.cyan.opacity(0.8) : Color.white.opacity(0.13), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }
}
