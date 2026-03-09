import SwiftUI

@MainActor
@Observable
final class ToastCenter {
    var message: String?
    var isPresented: Bool = false

    @ObservationIgnored
    private var dismissTask: Task<Void, Never>?

    func show(message: String, duration: TimeInterval = 3) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        dismissTask?.cancel()
        self.message = trimmed
        isPresented = true

        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.isPresented = false
            self?.message = nil
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        isPresented = false
        message = nil
    }
}

struct GlobalToastHost: View {
    @Environment(ToastCenter.self) private var toastCenter

    var body: some View {
        VStack {
            Spacer()
            if let message = toastCenter.message {
                ToastView(
                    message: message,
                    isPresented: Binding(
                        get: { toastCenter.isPresented },
                        set: { if !$0 { toastCenter.dismiss() } }
                    )
                )
            }
        }
        .allowsHitTesting(false)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: toastCenter.isPresented)
    }
}
