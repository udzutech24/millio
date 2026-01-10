// ShareRendering.swift
// Utilities for rendering share card and presenting share sheet

import SwiftUI
import Foundation

#if os(iOS)
import UIKit
import LinkPresentation

final class ImageItem: NSObject, UIActivityItemSource {
    private let image: UIImage
    private let jpegData: Data

    init(image: UIImage, compressionQuality: CGFloat = 0.92) {
        self.image = image
        self.jpegData = image.jpegData(compressionQuality: compressionQuality) ?? Data()
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return image
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return jpegData
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return "millio — курс за секунду"
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let meta = LPLinkMetadata()
        meta.title = "millio — курс за секунду"
        meta.iconProvider = NSItemProvider(object: image)
        return meta
    }
}
#endif

// MARK: - ShareRowModel
struct ShareRowModel: Identifiable {
    let id = UUID()
    let flag: String
    let code: String
    let value: String
}

// MARK: - ShareRow (View)
struct ShareRow: View {
    let flag: String
    let code: String
    let value: String
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Flag
            Text(flag)
                .font(.system(size: 48))
                .frame(width: 64, height: 64)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
                )

            // Main pill
            HStack {
                Text(code)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text(value)
                    .font(.system(size: 40, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .frame(height: 84)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        highlighted
                        ? LinearGradient(
                            colors: AppColors.coursesGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        : LinearGradient(
                            colors: [AppColors.textPrimary.opacity(0.10), AppColors.textPrimary.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: highlighted ? 1.6 : 0.8
                    )
            )
            .shadow(color: .black.opacity(0.25), radius: highlighted ? 10 : 8, x: 0, y: highlighted ? 6 : 4)
        }
    }
}

// MARK: - ShareCardView
struct ShareCardView: View {
    private let appName: String = "millio"
    private let slogan: String = "Курс за секунду. Делись красиво."

    let dateString: String
    let rows: [ShareRowModel]
    let highlightedCode: String

    var body: some View {
        ZStack {
            background

            VStack(alignment: .leading, spacing: 18) {
                header

                VStack(spacing: 8) {
                    ForEach(rows) { row in
                        ShareRow(
                            flag: row.flag,
                            code: row.code,
                            value: row.value,
                            highlighted: row.code.uppercased() == highlightedCode.uppercased()
                        )
                    }
                }
                .padding(.top, 4)

                // Небольшой “воздух”, но без огромной пустоты
                Spacer(minLength: 0)

                footer
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 14)
        }
        // Важно: фрейм задаётся снаружи при рендере (card.frame(width:..., height:...))
    }

    private var background: some View {
        LinearGradient(
            colors: AppColors.backgroundGradient,
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(
            RadialGradient(
                colors: [AppColors.coursesGradient.first!.opacity(0.18), .clear],
                center: .topLeading,
                startRadius: 80,
                endRadius: 520
            )
        )
        .overlay(
            RadialGradient(
                colors: [AppColors.coursesGradient.last!.opacity(0.18), .clear],
                center: .bottomTrailing,
                startRadius: 80,
                endRadius: 520
            )
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                        )

                    Image(systemName: "creditcard.and.123")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                }
                .frame(width: 28, height: 28)

                Text(appName)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()
            }

            Text(slogan)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            Text(dateString)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.70))
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Text("GET APP")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.8)
                )
            Spacer()
        }
        .padding(.top, 6)
    }
}

// MARK: - ShareRenderer
enum ShareRenderer {
    // Helpers for full-screen rendering based on device screen
    #if os(iOS)
        /// Returns a size in points that matches the device screen bounds, optionally multiplied
        /// to render at a higher virtual resolution while keeping the same aspect ratio.
        /// For example, multiplier 1 uses screen points, multiplier 3 triples both dimensions in points.
        static func screenRenderSize(multiplier: CGFloat = 1) -> CGSize {
            let screenBounds = UIScreen.main.bounds
            return CGSize(width: screenBounds.width * multiplier, height: screenBounds.height * multiplier)
        }

        /// Renders a card view to a UIImage sized to the device screen with the correct scale.
        /// - Parameters:
        ///   - card: The SwiftUI view to render.
        ///   - multiplier: Multiplies the size in points before rendering for extra detail.
        ///                 For exact pixel output matching the physical screen, pass `1` and we use UIScreen.main.scale.
        ///                 For extra crisp output, pass a higher multiplier (e.g., 2 or 3) and scale will still be UIScreen.main.scale.
        /// - Returns: Rendered UIImage or nil on non-iOS platforms.
        static func renderFullScreen<V: View>(card: V, multiplier: CGFloat = 1) -> UIImage? {
            let sizeInPoints = screenRenderSize(multiplier: multiplier)
            let deviceScale = UIScreen.main.scale
            return render(card: card, size: sizeInPoints, scale: deviceScale)
        }
    #endif

    static func render<V: View>(card: V, size: CGSize, scale: CGFloat = 3) -> UIImage? {
        #if os(iOS)
        let controller = UIHostingController(rootView: card)
        guard let view = controller.view else { return nil }

        view.bounds = CGRect(origin: .zero, size: size)
        view.backgroundColor = .clear
        view.overrideUserInterfaceStyle = .dark

        view.setNeedsLayout()
        view.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        #else
        return nil
        #endif
    }
}

// MARK: - ActivityView (Share Sheet)
#if os(iOS)
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Previews
#Preview("ShareCardView – Full Screen Mock") {
    let rows: [ShareRowModel] = [
        .init(flag: "🇺🇸", code: "USD", value: "92.54"),
        .init(flag: "🇪🇺", code: "EUR", value: "101.22"),
        .init(flag: "🇬🇧", code: "GBP", value: "118.47"),
        .init(flag: "🇯🇵", code: "JPY", value: "0.62")
    ]
    let date = Date()
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateStyle = .medium
    formatter.timeStyle = .short

    let card = ShareCardView(
        dateString: formatter.string(from: date),
        rows: rows,
        highlightedCode: "USD"
    )

    // Use a typical iPhone screen size in points for preview.
    // The actual export uses ShareRenderer helpers to match the real device.
    return card
        .frame(width: 390, height: 844) // iPhone 15/14 Pro-like size in points
}

