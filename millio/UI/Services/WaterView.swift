//
//  WaterView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct WaterView: View {
    var body: some View {
        ZStack {
            GradientBackground()
            
            VStack {
                Text("Вода")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
        .navigationTitle("Вода")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        WaterView()
    }
}
