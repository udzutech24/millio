//
//  CreditsView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct CreditsView: View {
    var body: some View {
        ZStack {
            GradientBackground()
            
            VStack {
                Text("Кредиты")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
        .navigationTitle("Кредиты")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        CreditsView()
    }
}
