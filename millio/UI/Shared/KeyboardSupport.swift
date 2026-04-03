//
//  KeyboardSupport.swift
//  millio
//

import SwiftUI
import UIKit

enum InputDismissalSupport {
    static func dismissActiveResponder() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

extension View {
    func dismissKeyboardOnTap() -> some View {
        onTapGesture {
            InputDismissalSupport.dismissActiveResponder()
        }
    }
}
