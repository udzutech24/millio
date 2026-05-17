import SwiftUI
import SwiftData

private func qaL(_ key: String) -> String { FinancesL10n.tr(key) }

private let orderDefaultsKey = "millio.audit.accountOrder"

// MARK: - Оркестратор флоу быстрой актуализации балансов

struct AccountQuickAuditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var accounts: [AuditableAccount] = []
    @State private var currentIndex = 0
    @State private var flowState: FlowState = .intro

    // Редактирование баланса
    @State private var currentBalance = ""
    @FocusState private var fieldFocused: Bool
    @State private var confirmFlash = false

    // Настройка порядка
    @State private var showReorderSheet = false
    @State private var showReminderSheet = false

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
            if flowState != .audit {
                Button(action: handleDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(AppSpacing.m)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .padding(AppSpacing.xl)
            }
        }
        .onAppear { loadAccounts() }
    }

    // MARK: - Dismiss — сохраняем всё и выходим

    private func handleDismiss() {
        if flowState == .audit {
            saveCurrentIfNeeded()
            commitAllPendingChanges()
        }
        dismiss()
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
                VStack(spacing: AppSpacing.m) {
                    startButton

                    HStack(spacing: AppSpacing.xl) {
                        Button {
                            showReorderSheet = true
                        } label: {
                            Label(qaL("finances.quick_audit.reorder"), systemImage: "line.3.horizontal")
                                .font(Font.millioCallout)
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        Button {
                            showReminderSheet = true
                        } label: {
                            Label(qaL("finances.quick_audit.reminder.button"), systemImage: "bell")
                                .font(Font.millioCallout)
                                .foregroundStyle(loadAuditReminderSettings().isEnabled
                                    ? AppColors.brandPrimary
                                    : AppColors.textSecondary
                                )
                        }
                    }
                }
            }
        }
        .padding(.bottom, AppSpacing.xxxl)
        .padding(.horizontal, AppSpacing.xl)
        .sheet(isPresented: $showReorderSheet) {
            reorderSheet
        }
        .sheet(isPresented: $showReminderSheet) {
            AccountAuditReminderView()
        }
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

    // MARK: - Reorder Sheet

    private var reorderSheet: some View {
        NavigationView {
            List {
                ForEach(accounts) { account in
                    HStack(spacing: AppSpacing.m) {
                        Image(systemName: account.iconName)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: account.accentColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 32, height: 32)
                            .background(
                                Circle().fill(account.accentColors.first?.opacity(0.15) ?? Color.clear)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.displayName)
                                .font(Font.millioBody)
                            Text(account.typeLabel)
                                .font(Font.millioCaption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer()
                        Text(auditFormattedBalance(account.balance, currency: account.currencyCode))
                            .font(Font.millioCaption)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(.vertical, 2)
                }
                .onMove { from, to in
                    accounts.move(fromOffsets: from, toOffset: to)
                    saveAccountOrder()
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(qaL("finances.quick_audit.reorder_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(qaL("finances.quick_audit.done")) {
                        showReorderSheet = false
                    }
                }
            }
        }
    }

    // MARK: - Audit

    private var auditView: some View {
        VStack(spacing: 0) {
            progressHeader
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.xxl)

            Spacer()

            VStack(spacing: AppSpacing.m) {
                if currentIndex > 0 {
                    AccountAuditInactiveRow(account: accounts[currentIndex - 1])
                        .padding(.horizontal, AppSpacing.xl)
                        .transition(.opacity)
                }

                AccountAuditActiveRow(
                    account: accounts[currentIndex],
                    balanceText: $currentBalance,
                    isFocused: $fieldFocused,
                    confirmFlash: confirmFlash
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

    private var progressBarColors: [Color] {
        guard !accounts.isEmpty else { return [AppColors.brandPrimary] }
        let isComplete = currentIndex + 1 >= accounts.count
        return isComplete
            ? [AppColors.positiveColor, Color(hex: "00E0B8")]
            : accounts[currentIndex].accentColors
    }

    private var progressHeader: some View {
        VStack(spacing: AppSpacing.s) {
            HStack(spacing: AppSpacing.s) {
                Text(qaL("finances.quick_audit.header"))
                    .font(Font.millioHeadline)
                    .foregroundStyle(AppColors.textSecondary)
                Text("\(currentIndex + 1) / \(accounts.count)")
                    .font(Font.millioCalloutSemibold)
                    .foregroundStyle(AppColors.textTertiary)
                Spacer()
                Button(action: handleDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(AppSpacing.s)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: progressBarColors,
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

            Button { commitAllPendingChanges(); dismiss() } label: {
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
        saveCurrentIfNeeded()
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
        withAnimation(.easeInOut(duration: 0.15)) { confirmFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.15)) { confirmFlash = false }
            moveToNext()
        }
    }

    private func saveCurrentIfNeeded() {
        guard !accounts.isEmpty else { return }
        if let value = parsedBalance(currentBalance), abs(value - accounts[currentIndex].balance) > 0.001 {
            applyBalance(value, at: currentIndex)
        }
    }

    private func parsedBalance(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned)
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
                let isQtyMode = inv.marketQuantity != nil && inv.lastKnownUnitPrice != nil
                result.append(AuditableAccount(
                    kind: .investment(inv),
                    balance: isQtyMode ? (inv.marketQuantity ?? 0) : inv.amount,
                    displayName: inv.name,
                    iconName: inv.resolvedIconName,
                    accentColors: AppColors.investmentsGradient,
                    typeLabel: qaL("finances.quick_audit.type_investment"),
                    typeIcon: "chart.line.uptrend.xyaxis",
                    currencyCode: inv.currency,
                    unitPrice: isQtyMode ? inv.lastKnownUnitPrice : nil,
                    unitCurrencyCode: isQtyMode ? (inv.marketCurrency ?? inv.currency) : nil
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

        // Применяем сохранённый пользователем порядок
        if let savedOrder = loadSavedOrder(), !savedOrder.isEmpty {
            let orderMap = savedOrder.enumerated().reduce(into: [String: Int]()) { dict, pair in
                if dict[pair.element] == nil { dict[pair.element] = pair.offset }
            }
            result.sort {
                (orderMap[$0.stableKey] ?? Int.max) < (orderMap[$1.stableKey] ?? Int.max)
            }
        }

        accounts = result
    }

    private func applyBalance(_ value: Double, at index: Int) {
        switch accounts[index].kind {
        case .card(let card):
            card.balance = value
        case .investment(let inv):
            if let price = accounts[index].unitPrice {
                inv.marketQuantity = value
                inv.amount = value * price
            } else {
                inv.amount = value
            }
        case .credit(let credit):
            credit.remainingAmount = value
        }
        accounts[index].balance = value
        do {
            try modelContext.save()
        } catch {
            print("[QuickAudit] modelContext.save error: \(error)")
        }
    }

    // Финальный коммит всех изменений — вызывается при выходе и в outro
    private func commitAllPendingChanges() {
        for (i, account) in accounts.enumerated() {
            switch account.kind {
            case .card(let card):
                if abs(card.balance - account.balance) > 0.001 { card.balance = account.balance }
            case .investment(let inv):
                if let price = account.unitPrice {
                    if abs((inv.marketQuantity ?? 0) - account.balance) > 0.001 {
                        inv.marketQuantity = account.balance
                        inv.amount = account.balance * price
                    }
                } else {
                    if abs(inv.amount - account.balance) > 0.001 { inv.amount = account.balance }
                }
            case .credit(let credit):
                if abs(credit.remainingAmount - account.balance) > 0.001 { credit.remainingAmount = account.balance }
            }
            _ = i
        }
        do {
            try modelContext.save()
        } catch {
            print("[QuickAudit] commitAll save error: \(error)")
        }
    }

    // MARK: - Порядок счетов (UserDefaults)

    private func loadSavedOrder() -> [String]? {
        guard let data = UserDefaults.standard.data(forKey: orderDefaultsKey),
              let order = try? JSONDecoder().decode([String].self, from: data)
        else { return nil }
        return order
    }

    private func saveAccountOrder() {
        let keys = accounts.map { $0.stableKey }
        if let data = try? JSONEncoder().encode(keys) {
            UserDefaults.standard.set(data, forKey: orderDefaultsKey)
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
