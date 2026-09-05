import SwiftUI

/// Двухцветная полоса «тело долга / проценты» одной строки графика платежей.
///
/// Аналога в проекте нет: `AccountHeroProgressBar` рисует одну величину на приглушённой дорожке,
/// здесь же значимы обе части и вместе они всегда дают 100 % платежа.
struct LoanShareBar: View {
    /// Доля тела долга в платеже, 0...1. Остаток полосы — проценты банку.
    let principalShare: Decimal
    var height: CGFloat = LoanScreenStyle.shareBarHeight

    var body: some View {
        let share = min(max(NSDecimalNumber(decimal: principalShare).doubleValue, 0), 1)
        return GeometryReader { proxy in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(LoanScreenStyle.principalColor)
                    .frame(width: proxy.size.width * share)
                Rectangle()
                    .fill(LoanScreenStyle.interestColor)
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
        // Полоса — картинка того же числа, что стоит в строке рядом: VoiceOver читает месяц и сумму.
        .accessibilityHidden(true)
    }
}
