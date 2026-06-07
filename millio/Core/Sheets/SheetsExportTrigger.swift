import Foundation

/// Fire-and-forget триггер инкрементальной синхронизации.
/// Вызывается после сохранения транзакции — не блокирует UI.
/// Данные для синхронизации передаются снаружи (CashflowViewModel знает о SwiftData).
actor SheetsExportTrigger {

    private let exportService: any SheetsExportServiceProtocol

    // Дебаунс: повторные вызовы в пределах окна схлопываются в один запрос.
    // Защищает от шторма при пакетном импорте транзакций.
    private static let debounceInterval: TimeInterval = 5
    private var pendingTask: Task<Void, Never>?

    init(exportService: any SheetsExportServiceProtocol) {
        self.exportService = exportService
    }

    func notifyTransactionAdded(with exportData: MillioExportData) async {
        // Не запускаем sync если аккаунт не подключён — избегаем 401 каждые 5 сек
        guard await exportService.getStatus().isConnected else { return }

        // Отменяем предыдущую отложенную задачу и стартуем новую
        pendingTask?.cancel()
        // Захватываем данные на момент вызова — они изменятся до истечения дебаунса
        pendingTask = Task { [exportData] in
            do {
                try await Task.sleep(for: .seconds(Self.debounceInterval))
            } catch {
                // Task отменена следующим вызовом — нормальное поведение
                return
            }

            guard !Task.isCancelled else { return }

            do {
                _ = try await exportService.syncNow(with: exportData)
                AppLogger.log(.info, category: "SheetsExport", "Инкрементальная синхронизация завершена.")
            } catch {
                // Ошибки sync не критичны — только логируем, не показываем пользователю
                AppLogger.log(.warning, category: "SheetsExport", "Инкрементальная синхронизация не удалась: \(error.localizedDescription)")
            }
        }
    }
}
