import SwiftUI

struct BackendDebugStatusContent: Equatable {
    let regionLine: String
    let baseURLLine: String
    let fallbackLine: String

    /// Intentionally available in release/TestFlight so QA can verify the auth target backend.
    static func make(
        regionCode: String,
        baseURLString: String,
        isFallbackActive: Bool
    ) -> BackendDebugStatusContent? {
        let trimmedBaseURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseURL.isEmpty else { return nil }

        let normalizedRegion = regionCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let regionLabel = normalizedRegion.isEmpty ? "AUTO" : normalizedRegion

        return BackendDebugStatusContent(
            regionLine: "Login backend: \(regionLabel)",
            baseURLLine: trimmedBaseURL,
            fallbackLine: "Fallback: \(isFallbackActive ? "on" : "off")"
        )
    }
}

struct BackendDebugStatusView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let content = BackendDebugStatusContent.make(
            regionCode: appState.backendRegionCode,
            baseURLString: appState.backendBaseURLString,
            isFallbackActive: appState.isBackendFallbackActive
        ) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(content.regionLine)
                Text(content.baseURLLine)
                Text(content.fallbackLine)
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 8)
            .padding(.trailing, 8)
            .allowsHitTesting(false)
        }
    }
}
