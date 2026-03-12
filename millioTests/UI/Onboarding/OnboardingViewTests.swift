import XCTest
import SwiftUI
import SwiftData
@testable import millio

@MainActor
final class OnboardingViewTests: XCTestCase {
    func testOnboardingStartsDirectlyFromQuickSetup() throws {
        let hosted = try makeHostedOnboardingView()

        XCTAssertNotNil(hosted.window)
        XCTAssertNil(hosted.hosting.view.findView(withAccessibilityIdentifier: "onboarding.startQuickSetupButton"))
    }

    private func makeHostedOnboardingView() throws -> HostedOnboardingView {
        let schema = Schema([Item.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let appState = AppState()
        appState.selectedLanguage = .russian
        let router = AppRouter()

        let rootView = OnboardingView(appState: appState, router: router)
            .environment(appState)
            .modelContainer(container)
            .preferredColorScheme(.dark)

        let hosting = UIHostingController(rootView: AnyView(rootView))
        let window = UIWindow(frame: CGRect(origin: .zero, size: CGSize(width: 390, height: 844)))
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

        return HostedOnboardingView(window: window, hosting: hosting)
    }
}

private extension UIView {
    func findView(withAccessibilityIdentifier identifier: String) -> UIView? {
        if accessibilityIdentifier == identifier {
            return self
        }
        for subview in subviews {
            if let match = subview.findView(withAccessibilityIdentifier: identifier) {
                return match
            }
        }
        return nil
    }
}

private struct HostedOnboardingView {
    let window: UIWindow
    let hosting: UIHostingController<AnyView>
}
