import SwiftUI
import XCTest
@testable import millio

@MainActor
final class AuthWelcomeViewTests: XCTestCase {
    func testAuthWelcomeDoesNotEmbedScrollViewOnCompactScreen() {
        let hosted = makeHostedAuthWelcomeView(size: CGSize(width: 320, height: 568))

        XCTAssertFalse(hosted.hosting.view.containsView(ofType: UIScrollView.self))
    }

    private func makeHostedAuthWelcomeView(size: CGSize) -> HostedAuthWelcomeView {
        let appState = AppState()
        let authManager = AuthManager()

        let rootView = AuthWelcomeView()
            .environment(appState)
            .environment(authManager)
            .preferredColorScheme(.dark)

        let hosting = UIHostingController(rootView: AnyView(rootView))
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = hosting
        hosting.loadViewIfNeeded()
        hosting.beginAppearanceTransition(true, animated: false)
        window.makeKeyAndVisible()

        hosting.view.frame = window.bounds
        window.layoutIfNeeded()
        hosting.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        window.layoutIfNeeded()
        hosting.view.layoutIfNeeded()
        hosting.endAppearanceTransition()

        return HostedAuthWelcomeView(window: window, hosting: hosting)
    }
}

private extension UIView {
    func containsView<T: UIView>(ofType type: T.Type) -> Bool {
        if self is T {
            return true
        }

        for subview in subviews where subview.containsView(ofType: type) {
            return true
        }

        return false
    }
}

private struct HostedAuthWelcomeView {
    let window: UIWindow
    let hosting: UIHostingController<AnyView>
}
