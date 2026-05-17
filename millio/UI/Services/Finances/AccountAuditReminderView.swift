import SwiftUI
import UserNotifications

private func qaL(_ key: String) -> String { FinancesL10n.tr(key) }

// MARK: - Модель настроек

struct AuditReminderSettings: Codable, Equatable {
    enum Frequency: String, Codable, CaseIterable {
        case weekly, biweekly, monthly

        var label: String {
            switch self {
            case .weekly:   return qaL("finances.quick_audit.reminder.freq_weekly")
            case .biweekly: return qaL("finances.quick_audit.reminder.freq_biweekly")
            case .monthly:  return qaL("finances.quick_audit.reminder.freq_monthly")
            }
        }
    }

    var isEnabled: Bool = false
    var frequency: Frequency = .weekly
    var weekday: Int = 4     // Calendar: 1=Вс,2=Пн,3=Вт,4=Ср,5=Чт,6=Пт,7=Сб
    var dayOfMonth: Int = 1  // 1–28
    var hour: Int = 10
    var minute: Int = 0
}

private let reminderDefaultsKey = "millio.audit.reminderSettings"
private let reminderIDPrefix = "millio.auditReminder."

// MARK: - Загрузка / сохранение настроек

func loadAuditReminderSettings() -> AuditReminderSettings {
    guard let data = UserDefaults.standard.data(forKey: reminderDefaultsKey),
          let s = try? JSONDecoder().decode(AuditReminderSettings.self, from: data)
    else { return AuditReminderSettings() }
    return s
}

private func saveAuditReminderSettings(_ s: AuditReminderSettings) {
    if let data = try? JSONEncoder().encode(s) {
        UserDefaults.standard.set(data, forKey: reminderDefaultsKey)
    }
}

// MARK: - Планирование уведомлений

func scheduleAuditReminders(_ settings: AuditReminderSettings) {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: existingReminderIDs())

    guard settings.isEnabled else { return }

    let content = UNMutableNotificationContent()
    content.title = qaL("finances.quick_audit.reminder.notif_title")
    content.body = qaL("finances.quick_audit.reminder.notif_body")
    content.sound = .default

    switch settings.frequency {
    case .weekly:
        var comps = DateComponents()
        comps.weekday = settings.weekday
        comps.hour = settings.hour
        comps.minute = settings.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let req = UNNotificationRequest(identifier: reminderIDPrefix + "weekly", content: content, trigger: trigger)
        center.add(req)

    case .biweekly:
        let now = Date()
        var cal = Calendar.current
        cal.locale = Locale.current
        var startComps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        startComps.weekday = settings.weekday
        startComps.hour = settings.hour
        startComps.minute = settings.minute
        startComps.second = 0
        var matchComps = DateComponents()
        matchComps.weekday = settings.weekday
        matchComps.hour = settings.hour
        matchComps.minute = settings.minute
        matchComps.second = 0
        guard var nextDate = cal.nextDate(
            after: now,
            matching: matchComps,
            matchingPolicy: .nextTimePreservingSmallerComponents
        ) else { return }

        for i in 0..<26 {
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: nextDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(
                identifier: reminderIDPrefix + "biweekly_\(i)",
                content: content,
                trigger: trigger
            )
            center.add(req)
            nextDate = cal.date(byAdding: .day, value: 14, to: nextDate) ?? nextDate
        }

    case .monthly:
        var comps = DateComponents()
        comps.day = min(settings.dayOfMonth, 28)
        comps.hour = settings.hour
        comps.minute = settings.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let req = UNNotificationRequest(identifier: reminderIDPrefix + "monthly", content: content, trigger: trigger)
        center.add(req)
    }
}

private func existingReminderIDs() -> [String] {
    var ids = [reminderIDPrefix + "weekly", reminderIDPrefix + "monthly"]
    for i in 0..<26 { ids.append(reminderIDPrefix + "biweekly_\(i)") }
    return ids
}

// MARK: - UI

struct AccountAuditReminderView: View {
    @State private var settings: AuditReminderSettings = loadAuditReminderSettings()
    @State private var showPermissionDeniedAlert = false
    @Environment(\.dismiss) private var dismiss

    private let weekdayLabels: [(Int, String)] = [
        (2, qaL("finances.quick_audit.reminder.mon")),
        (3, qaL("finances.quick_audit.reminder.tue")),
        (4, qaL("finances.quick_audit.reminder.wed")),
        (5, qaL("finances.quick_audit.reminder.thu")),
        (6, qaL("finances.quick_audit.reminder.fri")),
        (7, qaL("finances.quick_audit.reminder.sat")),
        (1, qaL("finances.quick_audit.reminder.sun")),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.l) {
                        enableToggleCard

                        if settings.isEnabled {
                            frequencyCard
                            dayCard
                            timeCard
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.l)
                    .animation(AppAnimation.springGentle, value: settings.isEnabled)
                    .animation(AppAnimation.springGentle, value: settings.frequency)
                }
            }
            .navigationTitle(qaL("finances.quick_audit.reminder.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(qaL("finances.quick_audit.reminder.done")) {
                        applyAndDismiss()
                    }
                    .font(Font.millioCalloutSemibold)
                    .foregroundStyle(AppColors.brandPrimary)
                }
            }
        }
        .alert(qaL("finances.quick_audit.reminder.permission_denied_title"), isPresented: $showPermissionDeniedAlert) {
            Button(qaL("finances.quick_audit.reminder.open_settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(qaL("finances.quick_audit.reminder.cancel"), role: .cancel) {
                settings.isEnabled = false
            }
        } message: {
            Text(qaL("finances.quick_audit.reminder.permission_denied_message"))
        }
    }

    // MARK: - Карточки

    private var enableToggleCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(qaL("finances.quick_audit.reminder.enable"))
                    .font(Font.millioBody)
                    .foregroundStyle(AppColors.textPrimary)
                Text(qaL("finances.quick_audit.reminder.enable_subtitle"))
                    .font(Font.millioCaption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
            Toggle("", isOn: $settings.isEnabled)
                .tint(AppColors.brandPrimary)
                .onChange(of: settings.isEnabled) { _, newValue in
                    if newValue { requestPermission() }
                }
        }
        .padding(AppSpacing.l)
        .background(cardBackground)
    }

    private var frequencyCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text(qaL("finances.quick_audit.reminder.frequency"))
                .font(Font.millioCaption)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppSpacing.xs)

            HStack(spacing: AppSpacing.s) {
                ForEach(AuditReminderSettings.Frequency.allCases, id: \.rawValue) { freq in
                    Button {
                        withAnimation(AppAnimation.springGentle) { settings.frequency = freq }
                    } label: {
                        Text(freq.label)
                            .font(Font.millioCaption)
                            .foregroundStyle(settings.frequency == freq ? .black : AppColors.textSecondary)
                            .padding(.horizontal, AppSpacing.m)
                            .padding(.vertical, AppSpacing.s)
                            .background(
                                Capsule().fill(settings.frequency == freq
                                    ? AnyShapeStyle(LinearGradient(colors: AppColors.financesGradient, startPoint: .leading, endPoint: .trailing))
                                    : AnyShapeStyle(Color.white.opacity(0.08))
                                )
                            )
                    }
                }
            }
        }
        .padding(AppSpacing.l)
        .background(cardBackground)
    }

    private var dayCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            if settings.frequency == .monthly {
                Text(qaL("finances.quick_audit.reminder.day_of_month"))
                    .font(Font.millioCaption)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.xs)

                Picker("", selection: $settings.dayOfMonth) {
                    ForEach(1...28, id: \.self) { day in
                        Text("\(day)").tag(day)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 100)
                .clipped()
            } else {
                Text(qaL("finances.quick_audit.reminder.weekday"))
                    .font(Font.millioCaption)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.xs)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.s) {
                        ForEach(weekdayLabels, id: \.0) { (num, label) in
                            Button {
                                settings.weekday = num
                            } label: {
                                Text(label)
                                    .font(Font.millioCaption)
                                    .foregroundStyle(settings.weekday == num ? .black : AppColors.textSecondary)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        Circle().fill(settings.weekday == num
                                            ? AnyShapeStyle(LinearGradient(colors: AppColors.financesGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                                            : AnyShapeStyle(Color.white.opacity(0.08))
                                        )
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.xs)
                }
            }
        }
        .padding(AppSpacing.l)
        .background(cardBackground)
    }

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text(qaL("finances.quick_audit.reminder.time"))
                .font(Font.millioCaption)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppSpacing.xs)

            DatePicker(
                "",
                selection: timeBinding,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 100)
            .clipped()
            .colorScheme(.dark)
        }
        .padding(AppSpacing.l)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: AppSpacing.l)
            .fill(.ultraThinMaterial)
    }

    // MARK: - Хелперы

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var comps = DateComponents()
                comps.hour = settings.hour
                comps.minute = settings.minute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.hour = comps.hour ?? 10
                settings.minute = comps.minute ?? 0
            }
        )
    }

    private func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                if !granted {
                    showPermissionDeniedAlert = true
                }
            }
        }
    }

    private func applyAndDismiss() {
        saveAuditReminderSettings(settings)
        scheduleAuditReminders(settings)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
