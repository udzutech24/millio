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
        HStack(spacing: 10) {
            Image("flag")
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(Color.white)
                .frame(width: 28, height: 28)
                .frame(width: 64, height: 64)
                .background(
                    Circle()
                        .fill(flagCircleBackground)
                )

            HStack {
                Text(code)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 134, height: 44)
                    .background(
                        Capsule(style: .continuous)
                            .fill(codePillBackground)
                    )

                Spacer()

                Text(value)
                    .font(.system(size: 36, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
            }
            .padding(.leading, highlighted ? 14 : 10)
            .padding(.trailing, 16)
            .frame(height: 64)
            .background(
                Capsule(style: .continuous)
                    .fill(rowBackground)
            )
        }
    }

    private var rowBackground: LinearGradient {
        if highlighted {
            return LinearGradient(
                colors: [Color(hex: "F7933A"), Color(hex: "F58A37")],
                startPoint: .leading,
                endPoint: .trailing
            )
        }

        return LinearGradient(
            colors: [Color(hex: "2F3035"), Color(hex: "25262A")],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var codePillBackground: Color {
        highlighted ? Color(hex: "E9B183") : Color(hex: "5A5C61")
    }

    private var flagCircleBackground: LinearGradient {
        if highlighted {
            return LinearGradient(
                colors: [Color(hex: "F79B41"), Color(hex: "F58A37")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [Color(hex: "34353A"), Color(hex: "26272B")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - ShareCardView
struct ShareCardView: View {
    let dateString: String
    let rows: [ShareRowModel]
    let highlightedCode: String

    var body: some View {
        ZStack {
            background

            VStack(alignment: .leading, spacing: 16) {
                header

                VStack(spacing: 10) {
                    ForEach(rows) { row in
                        ShareRow(
                            flag: row.flag,
                            code: row.code,
                            value: row.value,
                            highlighted: row.code.uppercased() == highlightedCode.uppercased()
                        )
                    }
                }
                .padding(.top, 2)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 16)
        }
    }

    private var background: some View {
        Color.black
        .overlay(
            RadialGradient(
                colors: [Color(hex: "F58A37").opacity(0.20), .clear],
                center: .topLeading,
                startRadius: 80,
                endRadius: 520
            )
        )
        .overlay(
            RadialGradient(
                colors: [Color(hex: "68A5FF").opacity(0.18), .clear],
                center: .bottomTrailing,
                startRadius: 80,
                endRadius: 520
            )
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Курсы")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Color.white)
                Spacer()
                Text("millio")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }

            Text(dateString)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.72))
        }
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
        dateString: formatter.string(from: date),
        rows: rows,
        highlightedCode: "USD"
    )

    // Use a typical iPhone screen size in points for preview.
    // The actual export uses ShareRenderer helpers to match the real device.
    return card
        .frame(width: 390, height: 844) // iPhone 15/14 Pro-like size in points
}
