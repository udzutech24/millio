//
//  LaunchingView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct LaunchingView: View {
    var body: some View {
        VStack {
            ProgressView()
            Text("loading")
                .foregroundStyle(.secondary)
                .padding(.top)
        }
    }
}

#Preview {
    LaunchingView()
}
