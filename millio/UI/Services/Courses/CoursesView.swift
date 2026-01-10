//
//  CoursesView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct CoursesView: View {
    var body: some View {
        ConverterView()
            .navigationTitle("Курсы")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        CoursesView()
    }
}
