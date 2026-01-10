//
//  CashbackView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct CashbackView: View {
    var body: some View {
        ZStack {
            GradientBackground()
            
            VStack {
                Text("Кешбэк")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
        .navigationTitle("Кешбэк")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        CashbackView()
    }
}
