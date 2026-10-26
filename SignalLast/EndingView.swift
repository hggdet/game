import SwiftUI

struct EndingView: View {
    let ending: GameEnding
    let state: GameState
    let onRetry: () -> Void
    let onMenu: () -> Void

    private var accent: Color {
        switch ending {
        case .earlyEscape: return Color(red: 0.35, green: 0.86, blue: 0.66)
        case .stationTruth: return Color(red: 0.30, green: 0.83, blue: 0.93)
        case .tragic: return Color(red: 0.95, green: 0.43, blue: 0.31)
        case .ambiguous: return Color(red: 0.68, green: 0.61, blue: 0.92)
        }
    }

    private var narrative: String {
        switch ending {
        case .earlyEscape:
            return "غادرت قبل اكتمال الأجزاء الخمسة. خرجت حياً، لكن سرّ المحطة ظل حبيساً في الداخل."
        case .stationTruth:
            return "جمعت الأجزاء الخمسة وأرسلت النداء. لم تكن المحطة مهجورة كما ظننت؛ كانت تنتظر من يعيد تشغيل الإشارة."
        case .tragic where state.savedSurvivor:
            return "اخترت ألا تترك الناجي خلفك. خرجتما معاً، لكن خطواته المذعورة أعادت Death Angel إلى أثرِكما."
        case .tragic where state.sacrificedLight:
            return "ضحّيت بالمصباح كي تمر الإشارة. انطفأ آخر ضوء في المحطة، وسمعت شيئاً يتحرك في العتمة."
        case .tragic:
            return "وصلت إلى الحقيقة، لكن شيئاً ثميناً ضاع في الطريق. بقي صدى الإشارة وحده يرافقك."
        case .ambiguous:
            return "انتظرت في الخزانة حتى آخر نبضة. بدأ صوت الإشارة… ثم انقطع. لم تعرف إن كان أحد قد سمعك."
        }
    }

    private var detail: String {
        switch ending {
        case .earlyEscape:
            return "نجاة قصيرة · \(state.collectedParts) من ٥ أجزاء"
        case .stationTruth:
            return "اكتمل النداء · \(state.points) نقطة"
        case .tragic:
            return state.savedSurvivor ? "اختيارك: إنقاذ الناجي" : "اختيارك: التضحية بالضوء"
        case .ambiguous:
            return "النهاية غير محسومة · صمت على الموجة"
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, accent.opacity(0.14), Color(red: 0.012, green: 0.018, blue: 0.026)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(accent.opacity(0.16))
                .frame(width: 290, height: 290)
                .blur(radius: 88)
                .offset(y: -210)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: 64)
                    Image(systemName: ending.symbol)
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(accent)
                        .frame(width: 92, height: 92)
                        .background(accent.opacity(0.11), in: Circle())
                        .overlay(Circle().stroke(accent.opacity(0.35), lineWidth: 1))
                        .shadow(color: accent.opacity(0.25), radius: 24)
                        .padding(.bottom, 28)

                    Text("النهاية \(ending == .earlyEscape ? "الأولى" : ending == .stationTruth ? "الثانية" : ending == .tragic ? "الثالثة" : "الرابعة")")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(accent.opacity(0.88))
                        .padding(.bottom, 9)
                    Text(ending.title)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(detail)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent.opacity(0.85))
                        .padding(.top, 12)

                    Text(narrative)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.83))
                        .multilineTextAlignment(.center)
                        .lineSpacing(6)
                        .padding(.horizontal, 32)
                        .padding(.top, 25)

                    VStack(spacing: 11) {
                        actionButton("محاولة جديدة", symbol: "arrow.counterclockwise", primary: true, action: onRetry)
                        actionButton("العودة إلى القائمة", symbol: "line.3.horizontal", primary: false, action: onMenu)
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 38)
                    .padding(.bottom, 36)
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            }
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
            .background(primary ? accent : Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(primary ? accent : Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
