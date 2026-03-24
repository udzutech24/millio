import SwiftUI

struct MiniAppQuickNavigationPopover: View {
    let destinations: [MiniAppDestination]
    let onSelect: (MiniAppDestination) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(destinations.enumerated()), id: \.element.id) { index, destination in
                Button {
                    onSelect(destination)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: destination.systemImage)
                            .font(.system(size: 17, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(destination.iconTint)
                            .frame(width: 22, alignment: .center)

                        Text(destination.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary.opacity(0.96))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < destinations.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 0.5)
                        .padding(.leading, 48)
                }
            }
        }
        .frame(minWidth: 198)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "181A20").opacity(0.98),
                            Color(hex: "10131A").opacity(0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.9)
                }
                .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 10)
        }
    }
}
