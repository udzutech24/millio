//
//  FirstStepsCard.swift
//  millio
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Модель шага

/// Куда карточка просит отвести пользователя по кнопке «Показать».
enum FirstStepAction {
    case addAccount
    case addExpense
    case openBackup
}

/// Срез данных, по которому считается выполненность шагов.
/// Собирается за один проход, чтобы каждый шаг не ходил в стор сам.
struct FirstStepsSnapshot {
    var hasCurrency: Bool
    var categoryCount: Int
    var accountCount: Int
    var transactionCount: Int
    var backupEnabled: Bool
}

/// Шаг чек-листа «Изучи millio».
/// Добавление нового шага = одна запись в `FirstStep.all`: счётчик, порядок и кнопка
/// «Показать» считаются от массива, switch'ей по конкретным шагам в коде нет.
struct FirstStep: Identifiable {
    let id: String
    let titleKey: String
    let isDone: (FirstStepsSnapshot) -> Bool
    let highlightID: String?
    let action: FirstStepAction?
}

extension FirstStep {
    static let all: [FirstStep] = [
        FirstStep(
            id: "currency",
            titleKey: "first_steps.step.currency",
            isDone: { $0.hasCurrency },
            highlightID: nil,
            action: nil
        ),
        FirstStep(
            id: "categories",
            titleKey: "first_steps.step.categories",
            isDone: { $0.categoryCount > 0 },
            highlightID: nil,
            action: nil
        ),
        FirstStep(
            id: "account",
            titleKey: "first_steps.step.account",
            isDone: { $0.accountCount > 0 },
            highlightID: "finances.addAccountButton",
            action: .addAccount
        ),
        FirstStep(
            id: "transaction",
            titleKey: "first_steps.step.transaction",
            isDone: { $0.transactionCount > 0 },
            highlightID: nil,
            action: .addExpense
        ),
        FirstStep(
            id: "backup",
            titleKey: "first_steps.step.backup",
            isDone: { $0.backupEnabled },
            highlightID: nil,
            action: .openBackup
        )
    ]

    static func doneCount(in snapshot: FirstStepsSnapshot) -> Int {
        all.filter { $0.isDone(snapshot) }.count
    }
}

// MARK: - Карточка

private enum Metrics {
    static let cardRadius: CGFloat = 20
    static let iconSide: CGFloat = 30
    static let iconRadius: CGFloat = 9
    static let checkboxSide: CGFloat = 20
    static let checkboxRadius: CGFloat = 6
    static let closeSide: CGFloat = 24
    static let hairline: CGFloat = 0.7
    static let checkboxStroke: CGFloat = 1.2
}

/// Виджет первых шагов. Удаляется штатно, как любой виджет дашборда: и крестиком,
/// и завершением чек-листа — поэтому отдельного флага «скрыт» не нужно, а у прошедшего
/// чек-лист пользователя виджета нет и его `@Query` не выполняются.
struct FirstStepsCard: View {
    var onAction: (FirstStep) -> Void
    var onRemove: () -> Void

    @AppStorage("firstSteps.collapsed") private var isCollapsed: Bool = false

    @Query private var categories: [CashflowCustomCategory]
    @Query private var accounts: [Account]
    @Query private var cards: [Card]
    @Query private var credits: [Credit]
    @Query private var investments: [Investment]
    @Query private var transactions: [CashflowTransaction]

    private var snapshot: FirstStepsSnapshot {
        FirstStepsSnapshot(
            hasCurrency: !SettingsManager.shared.primaryCurrencyCode.isEmpty,
            categoryCount: categories.count,
            // Счёт есть, если есть хоть что-то из четырёх: у части пользователей
            // счета до сих пор лежат легаси-типами Card/Credit/Investment.
            accountCount: accounts.count + cards.count + credits.count + investments.count,
            transactionCount: transactions.count,
            backupEnabled: SettingsManager.shared.isBackupEnabled
        )
    }

    private var doneCount: Int { FirstStep.doneCount(in: snapshot) }
    private var isComplete: Bool { doneCount == FirstStep.all.count }
    private var firstPending: FirstStep? { FirstStep.all.first { !$0.isDone(snapshot) } }

    var body: some View {
        card
            .onAppear {
                // Чек-лист был пройден до появления виджета (разовая инъекция принесла его
                // всем) — убираем молча, праздновать нечего.
                if isComplete { onRemove() }
            }
            .onChange(of: doneCount) { _, newValue in
                guard newValue == FirstStep.all.count else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onRemove()
            }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            header
            if !isCollapsed {
                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    ForEach(FirstStep.all) { step in
                        row(step)
                    }
                }
            }
        }
        .padding(AppSpacing.l)
        .background(DashboardCardBackground(cornerRadius: Metrics.cardRadius))
    }

    private var header: some View {
        HStack(spacing: AppSpacing.s) {
            brandIcon

            Text(L("first_steps.title"))
                .font(.millioHeadline)
                .foregroundStyle(.white)

            Spacer(minLength: AppSpacing.s)

            Text(String(format: L("first_steps.counter"), doneCount, FirstStep.all.count))
                .font(.millioCaption)
                .foregroundStyle(Color.white.opacity(0.45))

            Image(systemName: "chevron.down")
                .font(.millioCaption2)
                .foregroundStyle(Color.white.opacity(0.45))
                .rotationEffect(.degrees(isCollapsed ? 0 : 180))

            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.millioCaption2)
                    .foregroundStyle(Color.white.opacity(0.45))
                    .frame(width: Metrics.closeSide, height: Metrics.closeSide)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("first_steps.dismiss"))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(AppAnimation.springGentle) { isCollapsed.toggle() }
        }
    }

    private var brandIcon: some View {
        RoundedRectangle(cornerRadius: Metrics.iconRadius, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.iconRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: Metrics.hairline)
            )
            .overlay(
                Image(systemName: "wallet.pass")
                    .font(.millioBody)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppColors.premiumOrbBlue, AppColors.premiumOrbViolet],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .frame(width: Metrics.iconSide, height: Metrics.iconSide)
    }

    @ViewBuilder
    private func row(_ step: FirstStep) -> some View {
        let done = step.isDone(snapshot)

        HStack(spacing: AppSpacing.m) {
            checkbox(done: done)

            Text(L(String.LocalizationValue(step.titleKey)))
                .font(.millioCallout)
                .foregroundStyle(Color.white.opacity(done ? 0.40 : 0.85))
                .strikethrough(done, color: Color.white.opacity(0.40))

            Spacer(minLength: AppSpacing.s)

            // «Показать» только у первого невыполненного шага — чтобы вести по одному
            // действию за раз, а не предлагать пять входов сразу.
            if step.action != nil, step.id == firstPending?.id {
                Button {
                    onAction(step)
                } label: {
                    Text(L("first_steps.show"))
                        .font(.millioCaption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, AppSpacing.m)
                        .padding(.vertical, AppSpacing.xs)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    Capsule().stroke(Color.white.opacity(0.12), lineWidth: Metrics.hairline)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func checkbox(done: Bool) -> some View {
        RoundedRectangle(cornerRadius: Metrics.checkboxRadius, style: .continuous)
            .fill(done ? AppColors.brandPrimary.opacity(0.18) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.checkboxRadius, style: .continuous)
                    .stroke(AppColors.brandPrimary.opacity(0.55), lineWidth: Metrics.checkboxStroke)
            )
            .overlay {
                if done {
                    Image(systemName: "checkmark")
                        .font(.millioCaption2)
                        .foregroundStyle(AppColors.brandPrimary)
                }
            }
            .frame(width: Metrics.checkboxSide, height: Metrics.checkboxSide)
    }
}
