import SwiftUI

/// One root-chrome control for backend degradation. It stays outside `RootSceneIdentity`, so
/// late recovery cannot recreate the active screen, data scope, or in-progress input.
struct BackendAvailabilityIndicator: View {
    let availability: BackendAvailability
    let retry: () -> Void
    @State private var isExplanationPresented = false

    var body: some View {
        if case .offline = availability {
            Button {
                isExplanationPresented = true
            } label: {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.yellow)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Сервер Millio недоступен или не подтверждён")
            .accessibilityHint("Открывает описание состояния и повторную проверку")
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 10)
            .padding(.trailing, 16)
            .sheet(isPresented: $isExplanationPresented) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 36))
                            .foregroundStyle(.yellow)
                        Text("Backend Millio недоступен")
                            .font(.title2.bold())
                        Text("Локальные функции продолжают работать. Этот статус означает, что сервер Millio недоступен или ещё не подтвердил доступность — он не определяет наличие интернета на устройстве.")
                            .foregroundStyle(.secondary)
                        Button("Повторить проверку") {
                            isExplanationPresented = false
                            retry()
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                    .padding(24)
                    .navigationTitle("Статус сервиса")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium])
            }
        }
    }
}
