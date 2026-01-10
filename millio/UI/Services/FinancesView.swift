//
//  FinancesView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct FinancesView: View {
    var body: some View {
        ZStack {
            GradientBackground()
            
            VStack {
                Text("Финансы")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .navigationTitle("Финансы")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        FinancesView()
    }
}
