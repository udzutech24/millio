import SwiftUI

struct CashflowMonthPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Date
    @State private var month: Int
    @State private var year: Int

    private let calendar: Calendar
    private let yearRange: ClosedRange<Int>
    private let onConfirm: ((Date) -> Void)?

    init(
        selection: Binding<Date>,
        calendar: Calendar = .autoupdatingCurrent,
        onConfirm: ((Date) -> Void)? = nil
    ) {
        self._selection = selection
        self.calendar = calendar
        self.onConfirm = onConfirm
        let components = calendar.dateComponents([.year, .month], from: selection.wrappedValue)
        let selectedYear = components.year ?? calendar.component(.year, from: .now)
        _month = State(initialValue: components.month ?? 1)
        _year = State(initialValue: selectedYear)
        yearRange = (selectedYear - 15)...(selectedYear + 5)
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker(CashflowMonthWorkspaceLocalization.title, selection: $month) {
                    ForEach(1...12, id: \.self) { value in
                        Text(monthName(value)).tag(value)
                    }
                }
                Picker(CashflowMonthWorkspaceLocalization.year, selection: $year) {
                    ForEach(yearRange, id: \.self) { value in
                        Text(String(value)).tag(value)
                    }
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .navigationTitle(CashflowMonthWorkspaceLocalization.chooseMonth)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CashflowMonthWorkspaceLocalization.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(CashflowMonthWorkspaceLocalization.done) {
                        if let date = calendar.date(from: .init(year: year, month: month, day: 1)) {
                            let canonical = CashflowMonthSelectionPolicy.canonicalMonth(date, calendar: calendar)
                            selection = canonical
                            onConfirm?(canonical)
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(340)])
    }

    private func monthName(_ value: Int) -> String {
        var components = DateComponents(year: 2024, month: value, day: 1)
        components.calendar = calendar
        let date = calendar.date(from: components) ?? .now
        return date.formatted(.dateTime.month(.wide).locale(AppLocalization.currentAppLocale))
    }
}
