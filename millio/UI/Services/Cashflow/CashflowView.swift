//
//  CashflowView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI

struct CashflowView: View {
    var body: some View {
        ZStack {
            GradientBackground()
            
            VStack(spacing: 24) {
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(AppColors.textTertiary)
                
                Text("Кэшфлоу")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                
                Text("Скоро здесь появится функционал")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
        }
        .navigationTitle("Кэшфлоу")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        CashflowView()
    }
}
