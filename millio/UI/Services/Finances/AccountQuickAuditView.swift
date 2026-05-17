import SwiftUI
import SwiftData

private func qaL(_ key: String) -> String { FinancesL10n.tr(key) }

// MARK: - Оркестратор флоу быстрой актуализации балансов

struct AccountQuickAuditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var accounts: [AuditableAccount] = []
    @State private var currentIndex = 0
    @State private var flowState: FlowState = .intro
    @State private var currentBalance = ""
    @FocusState private var fieldFocused: Bool

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
                Text(qaL("finances.quick_audit.title"))
                    .font(Font.millioTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text(accounts.isEmpty ? qaL("finances.quick_audit.empty") : "\(accounts.count)")
                    .font(Font.millioBody)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Text(qaL("finances.quick_audit.description"))
                .font(Font.millioCalloutRegular)
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxxl)

            Spacer()

            if accounts.isEmpty {
                Text(qaL("finances.quick_audit.empty_hint"))
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
            Text(qaL("finances.quick_audit.start"))
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
        VStack(spacing: 0) {
            progressHeader
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.xxl)

            Spacer()

            // 3-slot: предыдущий (peek) → активный → следующий (peek)
            VStack(spacing: AppSpacing.m) {
                if currentIndex > 0 {
                    AccountAuditInactiveRow(account: accounts[currentIndex - 1])
                        .padding(.horizontal, AppSpacing.xl)
                        .transition(.opacity)
                }

                AccountAuditActiveRow(
                    account: accounts[currentIndex],
                    balanceText: $currentBalance,
                    isFocused: $fieldFocused
                )
                .padding(.horizontal, AppSpacing.xl)
                .id(currentIndex)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                )

                if currentIndex < accounts.count - 1 {
                    AccountAuditInactiveRow(account: accounts[currentIndex + 1])
                        .padding(.horizontal, AppSpacing.xl)
                        .transition(.opacity)
                }
            }
            .animation(AppAnimation.springGentle, value: currentIndex)

            Spacer()

            confirmButton
                .padding(.horizontal, AppSpacing.xl)
                .padding(.bottom, AppSpacing.xxxl)
        }
        .onAppear {
            currentBalance = auditBalanceForEditing(accounts[currentIndex].balance)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                fieldFocused = true
            }
        }
    }

    private var progressHeader: some View {
        VStack(spacing: AppSpacing.s) {
            HStack {
                Text(qaL("finances.quick_audit.header"))
                    .font(Font.millioHeadline)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Text("\(currentIndex + 1) / \(accounts.count)")
                    .font(Font.millioCalloutSemibold)
                    .foregroundStyle(AppColors.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: accounts[currentIndex].accentColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geo.size.width * CGFloat(currentIndex + 1) / CGFloat(max(accounts.count, 1)),
                            height: 3
                        )
                        .animation(AppAnimation.springGentle, value: currentIndex)
                }
            }
            .frame(height: 3)
        }
    }

    private var confirmButton: some View {
        Button(action: confirmAndAdvance) {
            HStack(spacing: AppSpacing.s) {
                Text(qaL("finances.quick_audit.confirm"))
                Image(systemName: "arrow.right")
            }
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
                Text(qaL("finances.quick_audit.done_title"))
                    .font(Font.millioTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text(qaL("finances.quick_audit.done_description"))
                    .font(Font.millioBody)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            Button { dismiss() } label: {
                Text(qaL("finances.quick_audit.done"))
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

    private func confirmAndAdvance() {
        let cleaned = currentBalance.replacingOccurrences(of: ",", with: ".")
        if let value = Double(cleaned), value != accounts[currentIndex].balance {
            applyBalance(value, at: currentIndex)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
        moveToNext()
    }

    private func moveToNext() {
        let nextIndex = currentIndex + 1
        if nextIndex >= accounts.count {
            fieldFocused = false
            withAnimation(AppAnimation.springGentle) { flowState = .outro }
        } else {
            withAnimation(AppAnimation.springGentle) { currentIndex = nextIndex }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                currentBalance = auditBalanceForEditing(accounts[nextIndex].balance)
                fieldFocused = true
            }
        }
    }

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
                    typeLabel: qaL("finances.quick_audit.type_card"),
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
                    typeLabel: qaL("finances.quick_audit.type_investment"),
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
                    typeLabel: qaL("finances.quick_audit.type_credit"),
                    typeIcon: "creditcard.trianglebadge.exclamationmark.fill",
                    currencyCode: credit.currency
                ))
            }
        }

        accounts = result
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
