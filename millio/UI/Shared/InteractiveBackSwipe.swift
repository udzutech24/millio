//
//  InteractiveBackSwipe.swift
//  millio
//

import SwiftUI

#if os(iOS)
import UIKit

enum InteractiveBackSwipePolicy {
    static func shouldEnableGesture(isEnabled: Bool, navigationStackDepth: Int) -> Bool {
        isEnabled && navigationStackDepth > 1
    }

    static func shouldBeginGesture(velocity: CGPoint) -> Bool {
        velocity.x > 0 && abs(velocity.x) > abs(velocity.y)
    }
}

private struct InteractiveBackSwipeBridge: UIViewControllerRepresentable {
    let isEnabled: Bool

    func makeUIViewController(context: Context) -> InteractiveBackSwipeController {
        InteractiveBackSwipeController(isEnabled: isEnabled)
    }

    func updateUIViewController(_ uiViewController: InteractiveBackSwipeController, context: Context) {
        uiViewController.isEnabled = isEnabled
        uiViewController.updateNavigationContext()
    }
}

private final class InteractiveBackSwipeController: UIViewController, UIGestureRecognizerDelegate {
    var isEnabled: Bool

    private weak var fullScreenPanGesture: UIPanGestureRecognizer?
    private weak var systemPopGesture: UIGestureRecognizer?

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = UIView()
        view.isHidden = true
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateNavigationContext()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateNavigationContext()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        removeFullScreenPanGestureIfNeeded()
        restoreSystemGestureIfNeeded()
    }

    func updateNavigationContext() {
        guard let navigationController else { return }

        let shouldEnable = InteractiveBackSwipePolicy.shouldEnableGesture(
            isEnabled: isEnabled,
            navigationStackDepth: navigationController.viewControllers.count
        )

        if shouldEnable {
            installFullScreenPanGestureIfNeeded(in: navigationController)
            navigationController.interactivePopGestureRecognizer?.isEnabled = false
        } else {
            removeFullScreenPanGestureIfNeeded()
            navigationController.interactivePopGestureRecognizer?.isEnabled = true
        }
    }

    private func installFullScreenPanGestureIfNeeded(in navigationController: UINavigationController) {
        guard fullScreenPanGesture == nil else { return }
        guard let systemGesture = navigationController.interactivePopGestureRecognizer else { return }
        guard let gestureView = systemGesture.view else { return }

        let selector = NSSelectorFromString("handleNavigationTransition:")
        let internalTargets = systemGesture.value(forKey: "targets") as? [NSObject]
        let internalTarget = internalTargets?.first?.value(forKey: "target")

        guard let internalTarget else { return }

        let panGesture = UIPanGestureRecognizer()
        panGesture.maximumNumberOfTouches = 1
        panGesture.cancelsTouchesInView = false
        panGesture.delegate = self
        panGesture.addTarget(internalTarget, action: selector)

        gestureView.addGestureRecognizer(panGesture)

        systemPopGesture = systemGesture
        fullScreenPanGesture = panGesture
    }

    private func removeFullScreenPanGestureIfNeeded() {
        guard let fullScreenPanGesture else { return }
        fullScreenPanGesture.view?.removeGestureRecognizer(fullScreenPanGesture)
    }

    private func restoreSystemGestureIfNeeded() {
        systemPopGesture?.isEnabled = true
    }

    private func belongsToTopViewController(of navigationController: UINavigationController) -> Bool {
        guard let topViewController = navigationController.topViewController else { return false }

        var current: UIViewController? = self
        while let controller = current {
            if controller === topViewController {
                return true
            }
            current = controller.parent
        }

        return false
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigationController else { return false }
        guard navigationController.viewControllers.count > 1 else { return false }
        guard belongsToTopViewController(of: navigationController) else { return false }
        guard navigationController.transitionCoordinator == nil else { return false }
        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else { return false }

        let velocity = panGesture.velocity(in: gestureRecognizer.view)
        return InteractiveBackSwipePolicy.shouldBeginGesture(velocity: velocity)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}
#endif

private struct InteractiveBackSwipeModifier: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        content.background(InteractiveBackSwipeBridge(isEnabled: isEnabled))
        #else
        content
        #endif
    }
}

extension View {
    /// Включает полноэкранный свайп-назад для экранов с кастомной кнопкой Back.
    func interactiveBackSwipe(isEnabled: Bool = true) -> some View {
        modifier(InteractiveBackSwipeModifier(isEnabled: isEnabled))
    }
}
