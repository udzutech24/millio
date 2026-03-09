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
            .navigationTitle(MainLocalization.text(MainLocalization.serviceCourses))
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        CoursesView()
    }
}
