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
            colors: [
                Color(red: 0.1, green: 0.2, blue: 0.35), // Темно-синий сверху
                Color(red: 0.15, green: 0.25, blue: 0.4), // Сине-зеленый
                Color(red: 0.2, green: 0.15, blue: 0.3), // Темно-фиолетовый снизу
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
