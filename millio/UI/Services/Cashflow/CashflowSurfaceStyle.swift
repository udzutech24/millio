import SwiftUI

/// Shared visual language for Cashflow surfaces. Keep hierarchy in reusable
/// tokens so child flows do not drift back to stock grouped-list styling.
enum CashflowSurfaceStyle {
    static let background = Color.black
    static let secondaryText = Color.white.opacity(0.78)
    static let panelFill = Color.white.opacity(0.035)
    static let separator = Color.white.opacity(0.16)
    static let positive = Color(hex: "4ECFA0")
    static let negative = Color(hex: "D45050")
    static let accent = Color(hex: "35B8DC")
    static let panelCornerRadius: CGFloat = 22
    static let rowCornerRadius: CGFloat = 16

    static func card(cornerRadius: CGFloat = panelCornerRadius) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(panelFill)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.28))
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 0.7)
            }
    }

    static func actionCard(isProminent: Bool) -> some View {
        RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
            .fill(Color.white.opacity(isProminent ? 0.075 : 0.05))
            .overlay {
                RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                    .stroke(
                        isProminent ? accent.opacity(0.34) : Color.white.opacity(0.10),
                        lineWidth: 0.8
                    )
            }
    }
}
