import AuthenticationServices
import SwiftUI

struct AuthWelcomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager

    private let featureItems: [(icon: String, title: LocalizedStringKey)] = [
        ("person.crop.circle.badge.checkmark", "Apple sign in"),
        ("lock.fill", "Private session"),
        ("sparkles", "Guest access")
    ]

    private var backendHost: String? {
        let host = Bundle.main.object(forInfoDictionaryKey: "AUTH_BASE_HOST") as? String
        let port = Bundle.main.object(forInfoDictionaryKey: "AUTH_BASE_PORT") as? String
        if let host, !host.isEmpty {
            if let port, !port.isEmpty {
                return "\(host):\(port)"
            }
            return host
        }

        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "AUTH_BASE_URL") as? String,
            let url = URL(string: raw)
        else {
            return nil
        }
        if let port = url.port {
            return "\(url.host() ?? raw):\(port)"
        }
        return url.host() ?? raw
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                GradientBackground(
                    topGradientColor: "153A7A",
                    topGradientFadeColor: "07111B",
                    bottomGradientColor: "6B93FF",
                    bottomGradientFadeColor: "04070D"
                )

                Circle()
                    .fill(Color(hex: "6B93FF").opacity(0.24))
                    .frame(width: 340, height: 340)
                    .blur(radius: 42)
                    .offset(x: -110, y: -280)

                Circle()
                    .fill(Color(hex: "C8A56A").opacity(0.18))
                    .frame(width: 260, height: 260)
                    .blur(radius: 48)
                    .offset(x: 120, y: -110)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        Spacer(minLength: 36)

                        header

                        Spacer(minLength: 12)

                        FinancesGlassCard(
                            accentColor: AppColors.brandPrimary,
                            cornerRadius: 34,
                            contentPadding: EdgeInsets(top: 28, leading: 24, bottom: 22, trailing: 24)
                        ) {
                            VStack(alignment: .leading, spacing: 28) {
                                hero
                                featureList
                                actionBlock
                            }
                        }
                    }
                    .frame(
                        minHeight: proxy.size.height - max(proxy.safeAreaInsets.bottom, 18),
                        alignment: .bottom
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 18))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 14, weight: .semibold))
                Text("PRIVATE ACCESS")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(1.8)
            }
            .foregroundStyle(Color.white.opacity(0.82))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.08))
            )

            Text("Millio")
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.88))
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Finance, without friction.")
                .font(.system(size: 40, weight: .bold, design: .serif))
                .foregroundStyle(Color.white)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Text("Use your Apple account for a full session, or enter as a guest and decide later.")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(featureItems, id: \.icon) { item in
                premiumPill(icon: item.icon, title: item.title)
            }
        }
    }

    private func premiumPill(icon: String, title: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 18)
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.white.opacity(0.8))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var actionBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await authManager.signIn(with: result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .disabled(authManager.isBusy)

            Button {
                appState.isGuestModeEnabled = true
            } label: {
                Text("Continue without account")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(authManager.isBusy)

            HStack {
                if let backendHost {
                    Text("Local backend: \(backendHost)")
                } else {
                    Text("Local backend auth")
                }

                Spacer()

                if authManager.isBusy {
                    ProgressView()
                        .tint(.white)
                }
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.55))

            if let errorMessage = authManager.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.92))
            }
        }
    }
}
