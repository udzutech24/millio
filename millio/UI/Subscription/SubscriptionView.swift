//
//  SubscriptionView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct SubscriptionView: View {
    var body: some View {
        ZStack {
            GradientBackground()
            
            VStack {
                Text("Подписка PRO")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .navigationTitle("Подписка")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SubscriptionView()
    }
}
