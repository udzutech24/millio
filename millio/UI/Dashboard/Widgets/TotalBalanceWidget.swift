//
//  TotalBalanceWidget.swift
//  millio

import SwiftUI

struct TotalBalanceWidget: View {
    let totalBalance: Double
    let displayCurrency: String
    var sparklinePoints: [Double] = []
    var weekDelta: (absolute: Double, percent: Double) = (0.0, 0.0)
    var sparklineDaysCount: Int = 7
    var isAmountHidden: Bool = false
    var onTap: (() -> Void)? = nil
    var onSparklineTap: (() -> Void)? = nil
    var onDaysChipTap: (() -> Void)? = nil

    private var formattedBalance: String {
        if isAmountHidden {
            let digits = Int(totalBalance.rounded())
            return String(repeating: "•", count: max(3, String(digits).count))
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: totalBalance)) ?? "—"
    }

    private var currencySymbol: String {
        MonetaCurrency(rawValue: displayCurrency)?.symbol ?? displayCurrency
    }

    private var deltaIsPositive: Bool { weekDelta.absolute >= 0 }
    private var hasDelta: Bool { abs(weekDelta.absolute) > 0.01 }

    private var formattedDelta: String {
        if isAmountHidden {
            let sign = deltaIsPositive ? "+" : ""
            let pct = String(format: "%.1f%%", weekDelta.percent)
            let digits = Int(abs(weekDelta.absolute).rounded())
            let masked = String(repeating: "•", count: max(3, String(digits).count))
            return "\(sign)\(masked)  \(sign)\(pct)"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        let sign = deltaIsPositive ? "+" : ""
        let abs = formatter.string(from: NSNumber(value: weekDelta.absolute)) ?? "—"
        let pct = String(format: "%.1f%%", weekDelta.percent)
        return "\(sign)\(abs)  \(sign)\(pct)"
    }

    var body: some View {
        HStack(spacing: 0) {
            // Левая зона: баланс + дельта → Счета
            VStack(alignment: .leading, spacing: 4) {
                Button(action: { onTap?() }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Общий баланс"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.55))

                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(formattedBalance)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(Color.white)
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)

                            Text(currencySymbol)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.75))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onTap == nil)

                // Чип дельты — вне кнопки баланса, иначе жесты конфликтуют
                if hasDelta {
                    let isNeutral = abs(weekDelta.percent) < 0.1
                    let deltaColor: Color = isNeutral
                        ? Color.white.opacity(0.45)
                        : deltaIsPositive ? AppColors.positiveColor : AppColors.negativeColor
                    if let onDaysChipTap {
                        Button(action: onDaysChipTap) {
                            deltaChip(text: formattedDelta, daysCount: sparklineDaysCount, color: deltaColor)
                        }
                        .buttonStyle(.plain)
                    } else {
                        deltaChip(text: formattedDelta, daysCount: sparklineDaysCount, color: deltaColor)
                    }
                }
            }

            Spacer(minLength: 12)

            // Правая зона: спарклайн → Динамика
            Button(action: { onSparklineTap?() }) {
                sparkline
                    .frame(width: 60, height: 36)
                    .contentShape(Rectangle().inset(by: -8))
            }
            .buttonStyle(.plain)
            .disabled(onSparklineTap == nil)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(cardBackground)
    }

    // MARK: - Delta chip

    private func deltaChip(text: String, daysCount: Int, color: Color) -> some View {
        HStack(spacing: 0) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
            if daysCount > 0 {
                Text("  ·  \(daysCount)\(L("dashboard.balance.days_suffix"))")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(color.opacity(0.65))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.15)))
    }

    // MARK: - Sparkline

    private var sparkline: some View {
        let points: [CGFloat] = sparklinePoints.isEmpty
            ? [0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]
            : sparklinePoints.map { CGFloat($0) }

        let isUp = (sparklinePoints.last ?? 0.5) >= (sparklinePoints.first ?? 0.5)
        let lineColor: Color = isUp
            ? AppColors.positiveColor
            : AppColors.negativeColor

        return Canvas { context, size in
            guard points.count > 1 else { return }
            let step = size.width / CGFloat(points.count - 1)
            var path = Path()
            for (i, value) in points.enumerated() {
                let x = CGFloat(i) * step
                let y = size.height * (1.0 - value)
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    let prev = CGPoint(x: CGFloat(i - 1) * step, y: size.height * (1.0 - points[i - 1]))
                    let curr = CGPoint(x: x, y: y)
                    let ctrl1 = CGPoint(x: prev.x + step * 0.5, y: prev.y)
                    let ctrl2 = CGPoint(x: curr.x - step * 0.5, y: curr.y)
                    path.addCurve(to: curr, control1: ctrl1, control2: ctrl2)
                }
            }
            context.stroke(
                path,
                with: .color(lineColor),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
            )
        }
    }

    // MARK: - Card background

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
            )
    }
}
