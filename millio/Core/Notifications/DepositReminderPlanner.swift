import Foundation

/// Вход `NotificationManager.scheduleAccountDepositMaturityReminder`, уже прошедший проверку правил.
struct DepositMaturityReminderRequest: Equatable, Sendable {
    let accountID: UUID
    let accountName: String
    let maturityDate: Date
}

/// Единственное место, где решается, положено ли вкладу напоминание о конце срока. До этого тот же
/// guard был скопирован в форму создания вклада и в правку условий — то есть жил во view и не мог
/// быть покрыт тестом.
enum DepositReminderPlanner {
    static func request(
        accountID: UUID,
        accountName: String,
        meta: DepositMeta?,
        now: Date
    ) -> DepositMaturityReminderRequest? {
        // `termEnd == nil` — накопительный счёт: срока нет, напоминать не о чем.
        // Прошедший срок тоже отсекаем здесь: планировщик уведомлений всё равно откажет,
        // но тогда решение «почему уведомления нет» было бы размазано по двум слоям.
        guard let meta, meta.remindEnd, let maturity = meta.termEnd, maturity > now else { return nil }
        return DepositMaturityReminderRequest(
            accountID: accountID,
            accountName: accountName,
            maturityDate: maturity
        )
    }
}
