import SwiftUI

struct RateAppBlock: View {
    let canOpenAppStoreReview: Bool
    let onRateInAppStore: () -> Void
    let onSendFeedback: () -> Void

    @State private var rating: Int = 0
    @State private var activeDialog: Dialog?

    private var dialogTitle: LocalizedStringKey {
        switch activeDialog {
        case .rateInAppStore:
            return "profile.rate_app.dialog.rate.title"
        case .sendFeedback:
            return "profile.rate_app.dialog.feedback.title"
        case .none:
            return LocalizedStringKey("")
        }
    }

    private var dialogMessage: LocalizedStringKey {
        switch activeDialog {
        case .rateInAppStore:
            return canOpenAppStoreReview
                ? "profile.rate_app.dialog.rate.message.app_store"
                : "profile.rate_app.dialog.rate.message.in_app"
        case .sendFeedback:
            return "profile.rate_app.dialog.feedback.message"
        case .none:
            return LocalizedStringKey("")
        }
    }

    private var rateActionTitle: LocalizedStringKey {
        canOpenAppStoreReview
            ? "profile.rate_app.dialog.rate.action.app_store"
            : "profile.rate_app.dialog.rate.action.in_app"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("profile.rate_app.block.title")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text("profile.rate_app.block.subtitle")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        rating = star
                        activeDialog = star == 5 ? .rateInAppStore : .sendFeedback
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(AppColors.brandPrimary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("profile.rate_app.star"))
                    .accessibilityValue(Text("\(star)"))
                    .accessibilityHint(Text("profile.rate_app.star_hint"))
                }

                Spacer(minLength: 0)
            }
        }
        .confirmationDialog(
            dialogTitle,
            isPresented: Binding(
                get: { activeDialog != nil },
                set: { if !$0 { activeDialog = nil } }
            ),
            titleVisibility: .visible
        ) {
            switch activeDialog {
            case .rateInAppStore:
                Button(rateActionTitle) {
                    onRateInAppStore()
                }
                Button("profile.rate_app.not_now", role: .cancel) {}

            case .sendFeedback:
                Button("profile.rate_app.dialog.feedback.action") {
                    onSendFeedback()
                }
                Button("profile.rate_app.not_now", role: .cancel) {}

            case .none:
                EmptyView()
            }
        } message: {
            Text(dialogMessage)
        }
    }
}

private extension RateAppBlock {
    enum Dialog {
        case rateInAppStore
        case sendFeedback
    }
}
