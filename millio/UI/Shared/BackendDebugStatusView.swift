import SwiftUI

#if DEBUG
struct BackendDebugStatusView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if !appState.backendBaseURLString.isEmpty {
            VStack(alignment: .trailing, spacing: 2) {
                Text("Backend: \(appState.backendRegionCode)")
                Text(appState.backendBaseURLString)
                Text("Fallback: \(appState.isBackendFallbackActive ? "on" : "off")")
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
#endif
