import SwiftUI

struct GameOverView: View {
    let onRetry: () -> Void
    let onMenu: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.20, green: 0.035, blue: 0.035), Color(red: 0.015, green: 0.018, blue: 0.024)],
                startPoint: .top,
                endPoint: .bottom
            )
            Circle()
                .fill(Color.red.opacity(0.16))
                .frame(width: 280, height: 280)
                .blur(radius: 90)
                .offset(y: -190)

            VStack(spacing: 0) {
                Spacer()
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Color.red.opacity(0.92))
                    .frame(width: 88, height: 88)
                    .background(Color.red.opacity(0.11), in: Circle())
                    .overlay(Circle().stroke(Color.red.opacity(0.38), lineWidth: 1))
                Text("انتهت الجولة")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 25)
                Text("وصل إليك أحد الصيادين. غيّر مسارك، أطفئ الضوء عند الحاجة، ولا تصدر صوتاً.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.76))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, 34)
                    .padding(.top, 15)
                Spacer()
                VStack(spacing: 11) {
                    actionButton("أعد المحاولة", symbol: "arrow.counterclockwise", primary: true, action: onRetry)
                    actionButton("العودة إلى القائمة", symbol: "line.3.horizontal", primary: false, action: onMenu)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 48)
            }
            .frame(maxWidth: 540)
        }
        .environment(\.layoutDirection, .rightToLeft)
        .preferredColorScheme(.dark)
    }

    private func actionButton(_ title: String, symbol: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                Text(title).font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundStyle(primary ? Color.black : Color.white.opacity(0.9))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(primary ? Color(red: 0.98, green: 0.39, blue: 0.31) : Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(primary ? Color.red.opacity(0.75) : Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
