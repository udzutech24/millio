//
//  UserSubscriptionsView.swift
//  millio
//

import SwiftUI
import SwiftData

struct UserSubscriptionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Query(sort: \UserSubscription.serviceName) private var subscriptions: [UserSubscription]

    @State private var showAddSheet = false
    @State private var editingSubscription: UserSubscription?

    private var activeSubscriptions: [UserSubscription] {
        subscriptions.filter(\.isActive)
    }

    private var displayCurrency: String {
        appState.primaryCurrencyCode.trimmingCharacters(in: .whitespaces).uppercased()
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if subscriptions.isEmpty {
                emptyState
            } else {
                subscriptionsList
            }
        }
        .navigationTitle(L("subscriptions.title", defaultValue: "Subscriptions"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            UserSubscriptionEditorSheet(modelContext: modelContext)
        }
        .sheet(item: $editingSubscription) { sub in
            UserSubscriptionEditorSheet(modelContext: modelContext, existing: sub)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Text("📋")
                .font(.system(size: 56))

            Text(L("subscriptions.empty.title", defaultValue: "No subscriptions yet"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white)

            Text(L("subscriptions.empty.subtitle",
                    defaultValue: "Track your recurring services — Netflix, Spotify, and others."))
                .font(.system(size: 15))
                .foregroundStyle(Color.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showAddSheet = true
            } label: {
                Text(L("subscriptions.add.first", defaultValue: "Add subscription"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: AppColors.subscriptionsGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .clipShape(Capsule())
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    // MARK: - List

    private var subscriptionsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                totalSection
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                ForEach(subscriptions) { sub in
                    subscriptionRow(sub)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }

                Color.clear.frame(height: 40)
            }
        }
    }

    private var totalSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("subscriptions.total.monthly", defaultValue: "Per month"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
            Text(formattedTotal)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Color.white)
        }
    }

    private var formattedTotal: String {
        let total = activeSubscriptions
            .filter { $0.currencyCode.uppercased() == displayCurrency }
            .reduce(0.0) { $0 + $1.monthlyAmount }
        let symbol = MonetaCurrency(rawValue: displayCurrency)?.symbol ?? displayCurrency
        let formatted = total.formatted(.number.precision(.fractionLength(0...2)))
        return "\(formatted) \(symbol)"
    }

    private func subscriptionRow(_ sub: UserSubscription) -> some View {
        Button {
            editingSubscription = sub
        } label: {
            HStack(spacing: 14) {
                Text(sub.iconEmoji)
                    .font(.system(size: 26))
                    .frame(width: 48, height: 48)
                    .background(
                        Color(hex: sub.colorHex).opacity(0.2)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(sub.serviceName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(sub.isActive ? Color.white : Color.white.opacity(0.4))

                    HStack(spacing: 6) {
                        Text(sub.billingCycle.localizedTitle)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.5))

                        if let next = sub.nextChargeDate {
                            Text("·")
                                .foregroundStyle(Color.white.opacity(0.3))
                            Text(next, style: .date)
                                .font(.system(size: 13))
                                .foregroundStyle(dueDateColor(for: next))
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    let symbol = MonetaCurrency(rawValue: sub.currencyCode.uppercased())?.symbol ?? sub.currencyCode
                    Text("\(sub.amount.formatted(.number.precision(.fractionLength(0...2)))) \(symbol)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(sub.isActive ? Color.white : Color.white.opacity(0.4))

                    if !sub.isActive {
                        Text(L("subscriptions.status.paused", defaultValue: "Paused"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                }
            }
            .padding(14)
            .background(Color(white: 0.1).clipShape(RoundedRectangle(cornerRadius: 16)))
        }
        .buttonStyle(.plain)
    }

    private func dueDateColor(for date: Date) -> Color {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days < 0 { return Color.red.opacity(0.8) }
        if days <= 3 { return Color.orange }
        return Color.white.opacity(0.5)
    }
}

// MARK: - Editor Sheet

private struct UserSubscriptionEditorSheet: View {
    let modelContext: ModelContext
    var existing: UserSubscription?

    @Environment(\.dismiss) private var dismiss

    @State private var serviceName: String = ""
    @State private var amount: String = ""
    @State private var currencyCode: String = "RUB"
    @State private var billingCycle: SubscriptionBillingCycle = .monthly
    @State private var nextChargeDate: Date = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var hasNextChargeDate: Bool = false
    @State private var iconEmoji: String = "💳"
    @State private var isActive: Bool = true
    @State private var note: String = ""

    private var isEditing: Bool { existing != nil }
    private var canSave: Bool { !serviceName.trimmingCharacters(in: .whitespaces).isEmpty && Double(amount) != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Form {
                    Section {
                        HStack {
                            TextField(
                                L("subscriptions.editor.emoji", defaultValue: "Emoji"),
                                text: $iconEmoji
                            )
                            .frame(width: 60)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 24))

                            TextField(
                                L("subscriptions.editor.name", defaultValue: "Service name"),
                                text: $serviceName
                            )
                        }
                    }
                    .listRowBackground(Color(white: 0.12))

                    Section {
                        HStack {
                            TextField(
                                L("subscriptions.editor.amount", defaultValue: "Amount"),
                                text: $amount
                            )
                            .keyboardType(.decimalPad)

                            TextField(
                                L("subscriptions.editor.currency", defaultValue: "Currency"),
                                text: $currencyCode
                            )
                            .frame(width: 70)
                            .textInputAutocapitalization(.characters)
                        }

                        Picker(
                            L("subscriptions.editor.cycle", defaultValue: "Billing"),
                            selection: $billingCycle
                        ) {
                            ForEach(SubscriptionBillingCycle.allCases, id: \.self) { cycle in
                                Text(cycle.localizedTitle).tag(cycle)
                            }
                        }
                    }
                    .listRowBackground(Color(white: 0.12))

                    Section {
                        Toggle(
                            L("subscriptions.editor.next_charge", defaultValue: "Next charge date"),
                            isOn: $hasNextChargeDate
                        )
                        if hasNextChargeDate {
                            DatePicker(
                                "",
                                selection: $nextChargeDate,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                        }
                    }
                    .listRowBackground(Color(white: 0.12))

                    Section {
                        Toggle(
                            L("subscriptions.editor.active", defaultValue: "Active"),
                            isOn: $isActive
                        )
                    }
                    .listRowBackground(Color(white: 0.12))

                    if isEditing {
                        Section {
                            Button(role: .destructive) {
                                if let sub = existing {
                                    modelContext.delete(sub)
                                    try? modelContext.save()
                                }
                                dismiss()
                            } label: {
                                Text(L("subscriptions.editor.delete", defaultValue: "Delete subscription"))
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .listRowBackground(Color(white: 0.12))
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(
                isEditing
                ? L("subscriptions.editor.title.edit", defaultValue: "Edit")
                : L("subscriptions.editor.title.add", defaultValue: "New subscription")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("cashflow.common.cancel", defaultValue: "Cancel")) { dismiss() }
                        .foregroundStyle(AppColors.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("cashflow.common.save", defaultValue: "Save")) {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear { populateFields() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func populateFields() {
        guard let sub = existing else { return }
        serviceName = sub.serviceName
        amount = sub.amount.formatted(.number.precision(.fractionLength(0...2)))
        currencyCode = sub.currencyCode
        billingCycle = sub.billingCycle
        hasNextChargeDate = sub.nextChargeDate != nil
        if let d = sub.nextChargeDate { nextChargeDate = d }
        iconEmoji = sub.iconEmoji
        isActive = sub.isActive
        note = sub.note ?? ""
    }

    private func save() {
        guard let amountValue = Double(amount.replacingOccurrences(of: ",", with: ".")) else { return }
        let name = serviceName.trimmingCharacters(in: .whitespaces)
        let currency = currencyCode.trimmingCharacters(in: .whitespaces).uppercased()

        if let sub = existing {
            sub.serviceName = name
            sub.amount = amountValue
            sub.currencyCode = currency
            sub.billingCycle = billingCycle
            sub.nextChargeDate = hasNextChargeDate ? nextChargeDate : nil
            sub.iconEmoji = iconEmoji.isEmpty ? "💳" : String(iconEmoji.prefix(2))
            sub.isActive = isActive
            sub.note = note.isEmpty ? nil : note
            sub.updatedAt = Date()
        } else {
            let sub = UserSubscription(
                serviceName: name,
                amount: amountValue,
                currencyCode: currency,
                billingCycle: billingCycle,
                nextChargeDate: hasNextChargeDate ? nextChargeDate : nil,
                iconEmoji: iconEmoji.isEmpty ? "💳" : String(iconEmoji.prefix(2)),
                note: note.isEmpty ? nil : note
            )
            sub.isActive = isActive
            modelContext.insert(sub)
        }

        try? modelContext.save()
        dismiss()
    }
}
