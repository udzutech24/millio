import SwiftUI

/// Общая "тёмная плашка" для второстепенных секций деталки счёта (налог, история и т.п.).
/// Единая форма нужна, чтобы «Налог» и «История» не расходились визуально — раньше налог
/// рисовался голым текстом на фоне экрана, а история — без рамки.
struct AccountDetailPlaqueSection<Content: View>: View {
    let title: String
    let caption: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack {
                Text(title)
                    .font(.millioBodySemibold)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: AppSpacing.s)
                if let caption, !caption.isEmpty {
                    Text(caption)
                        .font(.millioCaptionRegular)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            content()
        }
        .padding(AppSpacing.l)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.xl, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.xl, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
