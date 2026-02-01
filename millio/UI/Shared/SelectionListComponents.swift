//
//  SelectionListComponents.swift
//  millio
//
//  Created by Александр Сидоркин on 01.02.2026.
//

import SwiftUI

struct SelectionSectionCard<Content: View>: View {
    private let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(AppColors.textPrimary.opacity(0.10), lineWidth: 1)
                )
        )
    }
}

struct SelectionItemRow<Leading: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let dividerColor: Color
    let showDivider: Bool
    let onTap: () -> Void
    
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing
    
    var body: some View {
        HStack(spacing: 12) {
            leading()
                .frame(width: 18, height: 18)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)
                
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            
            Spacer(minLength: 8)
            
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(AppColors.brandPrimary)
            }
            
            trailing()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .overlay(alignment: .bottom) {
            if showDivider {
                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 1)
                    .padding(.leading, 18 + 18 + 12)
            }
        }
    }
}
