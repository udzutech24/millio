//
//  InteractiveBackSwipe.swift
//  millio
//

import SwiftUI

#if os(iOS)
import UIKit

enum InteractiveBackSwipePolicy {
    /// Возвращаем системный edge-swipe только когда экран действительно лежит не в корне стека.
    static func shouldEnableGesture(isEnabled: Bool, navigationStackDepth: Int) -> Bool {
        isEnabled && navigationStackDepth > 1
    }
}

private struct InteractiveBackSwipeEnabler: UIViewControllerRepresentable {
    let isEnabled: Bool

    func makeUIViewController(context: Context) -> InteractiveBackSwipeController {
        InteractiveBackSwipeController(isEnabled: isEnabled)
    }

    func updateUIViewController(_ uiViewController: InteractiveBackSwipeController, context: Context) {
        uiViewController.isEnabled = isEnabled
        uiViewController.updateInteractivePopGesture()
    }
}

private final class InteractiveBackSwipeController: UIViewController {
    var isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
        super.init(nibName: nil, bundle: nil)
        view.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateInteractivePopGesture()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateInteractivePopGesture()
    }

    func updateInteractivePopGesture() {
        guard let navigationController else { return }
        guard let gesture = navigationController.interactivePopGestureRecognizer else { return }

        let shouldEnable = InteractiveBackSwipePolicy.shouldEnableGesture(
            isEnabled: isEnabled,
            navigationStackDepth: navigationController.viewControllers.count
        )

        gesture.isEnabled = shouldEnable
        if shouldEnable {
            gesture.delegate = nil
        }
    }
}
#endif

private struct InteractiveBackSwipeModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        content.background(InteractiveBackSwipeEnabler(isEnabled: isEnabled))
        #else
        content
        #endif
    }
}

extension View {
    /// Восстанавливает системный свайп-назад для экранов с кастомной кнопкой Back.
    func interactiveBackSwipe(isEnabled: Bool = true) -> some View {
        modifier(InteractiveBackSwipeModifier(isEnabled: isEnabled))
    }
}
