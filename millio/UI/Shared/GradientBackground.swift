//
//  GradientBackground.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct GradientBackground: View {
    var body: some View {
        LinearGradient(
            colors: AppColors.backgroundGradient,
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
