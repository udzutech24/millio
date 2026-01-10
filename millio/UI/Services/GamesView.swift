//
//  GamesView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct GamesView: View {
    var body: some View {
        ZStack {
            GradientBackground()
            
            VStack {
                Text("Игры")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
        .navigationTitle("Игры")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        GamesView()
    }
}
