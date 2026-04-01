//
//  ErrorView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct ErrorView: View {
    let error: AppError
    @Bindable var appState: AppState
    @Bindable var router: AppRouter
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            
            Text(String(localized: "error"))
                .font(.title2)
                .bold()
            
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            
            Button(String(localized: "try_again")) {
                appState.lifecycle = .ready
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#Preview {
    ErrorView(
        error: .iCloudUnavailable,
        appState: AppState(),
        router: AppRouter()
    )
}
