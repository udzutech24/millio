import SwiftUI
import SwiftData

// MARK: - Оркестратор флоу быстрой актуализации балансов

struct AccountQuickAuditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var accounts: [AuditableAccount] = []
    @State private var currentIndex = 0
    @State private var flowState: FlowState = .intro

    enum FlowState: Equatable {
        case intro, audit, outro
    }

    var body: some View {
        ZStack {
            GradientBackground()

            switch flowState {
            case .intro:
                introView
                    .transition(.opacity)
            case .audit:
                auditView
                    .transition(.opacity)
            case .outro:
                outroView
                    .transition(.opacity)
            }
        }
        .animation(AppAnimation.springGentle, value: flowState)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(AppSpacing.m)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }
            .padding(AppSpacing.xl)
        }
        .onAppear { loadAccounts() }
    }

    // MARK: - Intro

    private var introView: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: AppColors.financesGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .symbolEffect(.rotate, options: .nonRepeating)

            VStack(spacing: AppSpacing.s) {
                Text("Проверка счетов")
                    .font(Font.millioTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text(accounts.isEmpty ? "Нет счетов" : "\(accounts.count) \(accountsPlural(accounts.count))")
                    .font(Font.millioBody)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Text("Пройдитесь по каждому счёту и подтвердите баланс.\nСвайп вправо — всё верно, влево — изменить.")
                .font(Font.millioCalloutRegular)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxxl)

            Spacer()

            if accounts.isEmpty {
                Text("Добавьте счета, чтобы использовать быструю проверку")
                    .font(Font.millioCallout)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
            } else {
                startButton
            }
        }
        .padding(.bottom, AppSpacing.xxxl)
        .padding(.horizontal, AppSpacing.xl)
    }

    private var startButton: some View {
        Button {
            withAnimation(AppAnimation.springGentle) { flowState = .audit }
        } label: {
            Text("Начать")
                .font(Font.millioHeadline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.l)
                .background(
                    LinearGradient(colors: AppColors.financesGradient, startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppSpacing.l))
        }
    }

    // MARK: - Audit

    private var auditView: some View {
        Group {
            if currentIndex < accounts.count {
                AccountAuditCardView(
                    account: accounts[currentIndex],
                    index: currentIndex,
                    total: accounts.count,
                    onConfirm: moveToNext,
                    onEdit: { newBalance in
                        applyBalance(newBalance, at: currentIndex)
                        moveToNext()
                    }
                )
                .id(currentIndex)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    )
                )
                .padding(.top, AppSpacing.xxxl)
            }
        }
    }

    // MARK: - Outro

    private var outroView: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            ZStack {
                ConfettiView()
                    .frame(width: 220, height: 220)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 84))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppColors.positiveColor, Color(hex: "00E0B8")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: AppSpacing.s) {
                Text("Всё проверено!")
                    .font(Font.millioTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Все \(accounts.count) \(accountsPlural(accounts.count)) актуализированы")
                    .font(Font.millioBody)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            Button { dismiss() } label: {
                Text("Готово")
                    .font(Font.millioHeadline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.l)
                    .background(
                        LinearGradient(colors: AppColors.financesGradient, startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppSpacing.l))
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.xxxl)
        }
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: - Логика

    private func loadAccounts() {
        var result: [AuditableAccount] = []

        if let cards = try? modelContext.fetch(FetchDescriptor<Card>()) {
            for card in cards {
                result.append(AuditableAccount(
                    kind: .card(card),
                    balance: card.balance,
                    displayName: card.name,
                    iconName: card.bank.icon,
                    accentColors: AppColors.cardIndexGradient,
                    typeLabel: "Карта",
                    typeIcon: "creditcard.fill",
                    currencyCode: card.currency
                ))
            }
        }

        if let investments = try? modelContext.fetch(FetchDescriptor<Investment>()) {
            for inv in investments {
                result.append(AuditableAccount(
                    kind: .investment(inv),
                    balance: inv.amount,
                    displayName: inv.name,
                    iconName: inv.resolvedIconName,
                    accentColors: AppColors.investmentsGradient,
                    typeLabel: "Актив",
                    typeIcon: "chart.line.uptrend.xyaxis",
                    currencyCode: inv.currency
                ))
            }
        }

        if let credits = try? modelContext.fetch(FetchDescriptor<Credit>()) {
            for credit in credits where !credit.isClosed {
                result.append(AuditableAccount(
                    kind: .credit(credit),
                    balance: credit.remainingAmount,
                    displayName: credit.name,
                    iconName: "banknote.fill",
                    accentColors: [Color(hex: "2B8CFF"), Color(hex: "005BFF")],
                    typeLabel: "Кредит",
                    typeIcon: "creditcard.trianglebadge.exclamationmark.fill",
                    currencyCode: credit.currency
                ))
            }
        }

        accounts = result
    }

    private func moveToNext() {
        if currentIndex + 1 >= accounts.count {
            withAnimation(AppAnimation.springGentle) { flowState = .outro }
        } else {
            withAnimation(AppAnimation.springGentle) { currentIndex += 1 }
        }
    }

    private func applyBalance(_ value: Double, at index: Int) {
        switch accounts[index].kind {
        case .card(let card):       card.balance = value
        case .investment(let inv):  inv.amount = value
        case .credit(let credit):   credit.remainingAmount = value
        }
        accounts[index].balance = value
        try? modelContext.save()
    }

    private func accountsPlural(_ n: Int) -> String {
        let mod10 = n % 10
        let mod100 = n % 100
        if mod100 >= 11 && mod100 <= 14 { return "счетов" }
        switch mod10 {
        case 1: return "счёт"
        case 2, 3, 4: return "счёта"
        default: return "счетов"
        }
    }
}

// MARK: - Конфетти

private struct ConfettiView: View {
    @State private var launched = false

    private struct Particle: Identifiable {
        let id = UUID()
        let angle: Double
        let radius: CGFloat
        let color: Color
        let size: CGFloat
        let delay: Double
    }

    private let particles: [Particle] = {
        let colors: [Color] = [
            Color(hex: "18C57A"), Color(hex: "68A5FF"),
            Color(hex: "FFD60A"), Color(hex: "FF6482"), Color(hex: "A855F7")
        ]
        return (0..<28).map { i in
            Particle(
                angle: Double(i) * (360.0 / 28.0) + Double.random(in: -8...8),
                radius: CGFloat.random(in: 55...105),
                color: colors[i % colors.count],
                size: CGFloat.random(in: 5...10),
                delay: Double.random(in: 0...0.15)
            )
        }
    }()

    var body: some View {
        ZStack {
            ForEach(particles) { p in
                Circle()
                    .fill(p.color)
                    .frame(width: p.size, height: p.size)
                    .offset(
                        x: launched ? cos(p.angle * .pi / 180) * p.radius : 0,
                        y: launched ? sin(p.angle * .pi / 180) * p.radius : 0
                    )
                    .opacity(launched ? 0 : 1)
                    .animation(
                        .easeOut(duration: 1.0).delay(p.delay),
                        value: launched
                    )
            }
        }
        .onAppear {
            withAnimation { launched = true }
        }
    }
}
