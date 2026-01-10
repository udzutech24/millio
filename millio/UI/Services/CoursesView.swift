//
//  CoursesView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct CoursesView: View {
    var body: some View {
        ZStack {
            GradientBackground()
            
            VStack {
                Text("Курсы")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .navigationTitle("Курсы")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        CoursesView()
    }
}
