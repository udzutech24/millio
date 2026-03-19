// ShareRendering.swift
// Utilities for rendering share card and presenting share sheet

import SwiftUI
import Foundation

#if os(iOS)
import UIKit
import LinkPresentation
import CoreImage.CIFilterBuiltins

final class ImageItem: NSObject, UIActivityItemSource {
    private let image: UIImage
    private let jpegData: Data
    private let subject: String

    init(image: UIImage, compressionQuality: CGFloat = 0.92, subject: String = ConverterL10n.shareSheetDefaultSubject) {
        self.image = image
        self.jpegData = image.jpegData(compressionQuality: compressionQuality) ?? Data()
        self.subject = subject
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return image
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return jpegData
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return subject
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let meta = LPLinkMetadata()
        meta.title = subject
        meta.iconProvider = NSItemProvider(object: image)
        return meta
    }
}

enum ShareQRCodeGenerator {
    #if os(iOS)
    private static let context = CIContext()
    private static let filter = CIFilter.qrCodeGenerator()

    static func image(for string: String, size: CGFloat) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }
        let scaleX = max(1, size / outputImage.extent.width)
        let scaleY = max(1, size / outputImage.extent.height)
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
    #endif
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
        HStack(spacing: 8) {
            flagIcon

            HStack(spacing: 10) {
                Text(code)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))

                if highlighted {
                    Image(systemName: "circle.grid.3x3.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.09)))
                }

                Spacer()
                Text(value)
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.95))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            .padding(.leading, 18)
            .padding(.trailing, 20)
            .frame(height: 76)
            .background(
                Capsule(style: .continuous)
                    .fill(rowBackground)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(rowBorderStyle, lineWidth: 1)
            )
            .shadow(color: highlighted ? Color(hex: "47D7FF").opacity(0.14) : .clear, radius: 10, x: 0, y: 0)
        }
    }

    @ViewBuilder
    private var flagIcon: some View {
        if let assetName = CurrencyFlags.assetName(for: code) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .frame(width: 76, height: 76)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(hex: "141A25"))
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        } else {
            let fallbackEmoji = CurrencyFlags.flag(for: code)
            if fallbackEmoji != "🏳️" {
                Text(fallbackEmoji)
                    .font(.system(size: 28))
                    .frame(width: 76, height: 76)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(hex: "141A25"))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            } else {
                Image("flag")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(Color.white)
                    .frame(width: 24, height: 24)
                    .frame(width: 76, height: 76)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(hex: "141A25"))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
        }
    }

    private var rowBackground: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "1F2430"), Color(hex: "1A1F2B")],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var rowBorderStyle: AnyShapeStyle {
        if highlighted {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color(hex: "47D7FF").opacity(0.8), Color(hex: "8A6BFF").opacity(0.72)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        return AnyShapeStyle(Color.white.opacity(0.08))
    }
}

// MARK: - ShareCardView
struct ShareCardView: View {
    let locale: Locale
    let dateString: String
    let rows: [ShareRowModel]
    let highlightedCode: String
    let baseSummary: String
    let appStoreURLText: String

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    ForEach(rows) { row in
                        ShareRow(
                            flag: row.flag,
                            code: row.code,
                            value: row.value,
                            highlighted: row.code.uppercased() == highlightedCode.uppercased()
                        )
                    }
                }
                .padding(.bottom, 16)

                footerBranding
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var footerBranding: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(ConverterL10n.sharePromoBrand)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "47D7FF"), Color(hex: "8A6BFF")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Text(ConverterL10n.sharePromoSubtitle(locale: locale))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(2)

                Text(ConverterL10n.shareMetaLine(dateString: dateString, baseSummary: baseSummary, locale: locale))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.56))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            shareQRCode
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "141A25").opacity(0.95), Color(hex: "11161F").opacity(0.94)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var shareQRCode: some View {
        #if os(iOS)
        if let image = ShareQRCodeGenerator.image(for: appStoreURLText, size: 72) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: 84, height: 84)
        }
        #else
        EmptyView()
        #endif
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
    var onComplete: ((Bool) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onComplete?(completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Previews
#Preview("ShareCardView – Full Screen Mock") {
    let rows: [ShareRowModel] = [
        .init(flag: "", code: "USD", value: "92.54"),
        .init(flag: "", code: "EUR", value: "101.22"),
        .init(flag: "", code: "GBP", value: "118.47"),
        .init(flag: "", code: "JPY", value: "0.62")
    ]
    let date = Date()
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateStyle = .medium
    formatter.timeStyle = .short

    let card = ShareCardView(
        locale: Locale(identifier: "ru_RU"),
        dateString: formatter.string(from: date),
        rows: rows,
        highlightedCode: "USD",
        baseSummary: ConverterL10n.baseSummary(input: "1", code: "USD"),
        appStoreURLText: AppStoreReviewLink.appURL?.absoluteString ?? "https://apps.apple.com/app/id\(AppStoreReviewLink.fallbackAppStoreID)"
    )

    // Use a typical iPhone screen size in points for preview.
    // The actual export uses ShareRenderer helpers to match the real device.
    return card
        .frame(width: 390, height: 844) // iPhone 15/14 Pro-like size in points
}
