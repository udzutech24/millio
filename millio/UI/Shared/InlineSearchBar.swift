//
//  InlineSearchBar.swift
//  millio
//
//  Created by Александр Сидоркин on 13.02.2026.
//

import SwiftUI

struct InlineSearchBar: View {
    @Binding var text: String
    var placeholder: String
    
    var body: some View {
        let accentColor = AppColors.financesGradient.first ?? .cyan
        let fillGradient = LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.07, blue: 0.11),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        let glowGradient = LinearGradient(
            colors: [
                accentColor.opacity(0.18),
                Color.clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        
        HStack(spacing: AppSpacing.m) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(AppColors.textTertiary)

            TextField(placeholder, text: $text)
                .font(.system(size: 17))
                .foregroundStyle(AppColors.textPrimary)
                .tint(AppColors.brandPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.l)
        .padding(.vertical, AppSpacing.m)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(fillGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(glowGradient)
                        .opacity(0.6)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(accentColor.opacity(0.55), lineWidth: 1)
        }
    }
}

#Preview {
    ZStack {
        Color.black
        InlineSearchBar(text: .constant(""), placeholder: "Search")
            .padding()
    }
}
