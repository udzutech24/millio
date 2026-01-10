//
//  HabitsView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct HabitsView: View {
    var body: some View {
        ZStack {
            GradientBackground()
            
            VStack {
                Text("Привычки")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
        .navigationTitle("Привычки")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        HabitsView()
    }
}
