import SwiftUI
import UIKit

struct ErrorView: View {
    let details: AppErrorInfo
    let logSaved: Bool
    let onDismiss: () -> Void

    @State private var didCopy = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [Color.black, Color(red: 0.19, green: 0.035, blue: 0.045), Color(red: 0.015, green: 0.018, blue: 0.024)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        Spacer(minLength: 12)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 31, weight: .medium))
                            .foregroundStyle(Color.orange)
                            .frame(width: 68, height: 68)
                            .background(Color.orange.opacity(0.12), in: Circle())
                            .overlay(Circle().stroke(Color.orange.opacity(0.35), lineWidth: 1))

                        Text("حدث خطأ")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)

                        Text(details.message)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .frame(maxWidth: 470)

                        VStack(alignment: .leading, spacing: 7) {
                            Text("الموضع")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.56))
                            Text("\(details.file):\(details.line)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.cyan.opacity(0.95))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(logSaved
                                 ? "حُفظت التفاصيل في Documents/\(AppErrorLogger.fileName)"
                                 : "تعذّر حفظ السجل؛ انسخ التفاصيل أدناه.")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.56))
                        }
                        .padding(12)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Button {
                            let logStatus = logSaved
                                ? "Documents/\(AppErrorLogger.fileName)"
                                : "لم يُحفظ سجل التفاصيل في Documents."
                            UIPasteboard.general.string = "\(details.copyText)\n\(logStatus)"
                            didCopy = true
                        } label: {
                            Label(didCopy ? "تم النسخ" : "نسخ تفاصيل الخطأ", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(Color.cyan, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button("العودة إلى القائمة", action: onDismiss)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.86))
                            .padding(.vertical, 4)
                        Spacer(minLength: 12)
                    }
                    .padding(20)
                    .frame(maxWidth: 520, minHeight: geometry.size.height)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
                    .padding(.horizontal, 16)
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
        .preferredColorScheme(.dark)
    }
}
