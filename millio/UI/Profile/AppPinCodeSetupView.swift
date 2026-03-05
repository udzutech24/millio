//
//  AppPinCodeSetupView.swift
//  millio
//
//  Created by Александр Сидоркин on 21.02.2026.
//

import SwiftUI

struct AppPinCodeSetupView: View {
    enum Mode {
        case create
        case change
    }

    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    let onSaved: () -> Void

    @State private var step: Step = .enterNew
    @State private var enteredPin = ""
    @State private var firstPin = ""
    @State private var errorText: String?

    private enum Step {
        case verifyCurrent
        case enterNew
        case confirmNew
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                VStack(spacing: 20) {
                    Spacer(minLength: 8)

                    Text(stepTitle)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)

                    pinDots

                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(AppColors.error)
                    }

                    pinPad
                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 24)
            }
            .navigationTitle(mode == .create ? "PIN code" : "Change PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                if mode == .change {
                    step = .verifyCurrent
                }
            }
        }
    }

    private var stepTitle: String {
        switch step {
        case .verifyCurrent:
            return "Enter current PIN"
        case .enterNew:
            return "Enter new PIN"
        case .confirmNew:
            return "Re-enter new PIN"
        }
    }

    private var pinDots: some View {
        HStack(spacing: 14) {
            ForEach(0..<4, id: \.self) { idx in
                Circle()
                    .fill(idx < enteredPin.count ? AppColors.brandPrimary : AppColors.textPrimary.opacity(0.25))
                    .frame(width: 14, height: 14)
            }
        }
        .frame(height: 30)
    }

    private var pinPad: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)
        let values = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"]

        return LazyVGrid(columns: columns, spacing: 14) {
            ForEach(values, id: \.self) { value in
                if value.isEmpty {
                    Color.clear
                        .frame(height: 56)
                } else {
                    Button {
                        handleKey(value)
                    } label: {
                        Text(value)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
    }

    private func handleKey(_ key: String) {
        errorText = nil
        if key == "⌫" {
            guard !enteredPin.isEmpty else { return }
            enteredPin.removeLast()
            return
        }
        guard enteredPin.count < 4, key.allSatisfy(\.isNumber) else { return }
        enteredPin.append(key)
        guard enteredPin.count == 4 else { return }
        handleEnteredPin()
    }

    private func handleEnteredPin() {
        switch step {
        case .verifyCurrent:
            guard AppLockPinStore.shared.verify(pin: enteredPin) else {
                errorText = "Current PIN is incorrect"
                enteredPin = ""
                return
            }
            enteredPin = ""
            step = .enterNew
        case .enterNew:
            firstPin = enteredPin
            enteredPin = ""
            step = .confirmNew
        case .confirmNew:
            guard enteredPin == firstPin else {
                errorText = "PIN codes do not match"
                firstPin = ""
                enteredPin = ""
                step = .enterNew
                return
            }
            do {
                try AppLockPinStore.shared.save(pin: enteredPin)
                onSaved()
                dismiss()
            } catch {
                errorText = "Failed to save PIN"
                firstPin = ""
                enteredPin = ""
                step = .enterNew
            }
        }
    }
}

#Preview {
    AppPinCodeSetupView(mode: .create, onSaved: {})
}
