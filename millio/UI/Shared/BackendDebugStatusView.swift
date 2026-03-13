import SwiftUI

struct BackendDebugStatusContent: Equatable {
    let regionLine: String
    let baseURLLine: String
    let fallbackLine: String
    let selectionLine: String?

    /// Intentionally available in release/TestFlight so QA can verify the auth target backend.
    static func make(
        regionCode: String,
        baseURLString: String,
        isFallbackActive: Bool,
        selectionSummary: String
    ) -> BackendDebugStatusContent? {
        let trimmedBaseURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseURL.isEmpty else { return nil }

        let normalizedRegion = regionCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let regionLabel = normalizedRegion.isEmpty ? "AUTO" : normalizedRegion
        let trimmedSelectionSummary = selectionSummary.trimmingCharacters(in: .whitespacesAndNewlines)

        return BackendDebugStatusContent(
            regionLine: "Login backend: \(regionLabel)",
            baseURLLine: trimmedBaseURL,
            fallbackLine: "Fallback: \(isFallbackActive ? "on" : "off")",
            selectionLine: trimmedSelectionSummary.isEmpty ? nil : trimmedSelectionSummary
        )
    }
}

struct BackendDebugStatusView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let content = BackendDebugStatusContent.make(
            regionCode: appState.backendRegionCode,
            baseURLString: appState.backendBaseURLString,
            isFallbackActive: appState.isBackendFallbackActive,
            selectionSummary: appState.backendSelectionSummary
        ) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(content.regionLine)
                Text(content.baseURLLine)
                Text(content.fallbackLine)
                if let selectionLine = content.selectionLine {
                    Text(selectionLine)
                }
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
