import SwiftUI

struct GameOverView: View {
    let checkpointTitle: String?
    let onRetry: () -> Void
    let onMenu: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.20, green: 0.035, blue: 0.035), Color(red: 0.015, green: 0.018, blue: 0.024)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                Circle()
                    .fill(Color.red.opacity(0.16))
                    .frame(width: 260, height: 260)
                    .blur(radius: 85)
                    .offset(y: -170)
                    .allowsHitTesting(false)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 12)
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(Color.red.opacity(0.92))
                            .frame(width: 70, height: 70)
                            .background(Color.red.opacity(0.11), in: Circle())
                            .overlay(Circle().stroke(Color.red.opacity(0.38), lineWidth: 1))
                        Text("انتهت الجولة")
                            .font(.system(size: 27, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.top, 15)
                        Text("وصل إليك أحد الصيادين. غيّر مسارك، أطفئ الضوء عند الحاجة، ولا تصدر صوتاً.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.76))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 28)
                            .padding(.top, 10)
                            .frame(maxWidth: 480)

                        if let checkpointTitle {
                            Label("آخر نقطة حفظ: \(checkpointTitle)", systemImage: "flag.checkered")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.orange.opacity(0.92))
                                .padding(.top, 12)
                        } else {
                            Text("لم تُفتح نقطة تحقق بعد؛ ستبدأ المحاولة من البداية.")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.58))
                                .padding(.top, 12)
                        }

                        Spacer(minLength: 14)
                        VStack(spacing: 9) {
                            actionButton(
                                checkpointTitle == nil ? "أعد المحاولة من البداية" : "أعد المحاولة من نقطة الحفظ",
                                symbol: "arrow.counterclockwise",
                                primary: true,
                                action: onRetry
                            )
                            actionButton("العودة إلى القائمة", symbol: "line.3.horizontal", primary: false, action: onMenu)
                        }
                        .padding(.horizontal, 24)
                        .frame(maxWidth: 460)
                        Spacer(minLength: 14)
                    }
                    .frame(maxWidth: 540, minHeight: geometry.size.height)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
        .preferredColorScheme(.dark)
    }

    private func actionButton(_ title: String, symbol: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                Text(title).font(.system(size: 13, weight: .bold, design: .rounded))
            }
            .foregroundStyle(primary ? Color.black : Color.white.opacity(0.9))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(primary ? Color(red: 0.98, green: 0.39, blue: 0.31) : Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(primary ? Color.red.opacity(0.75) : Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
