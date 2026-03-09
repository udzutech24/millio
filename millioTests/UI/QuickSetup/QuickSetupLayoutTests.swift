import XCTest
import SwiftUI
import SwiftData
@testable import millio

@MainActor
final class QuickSetupLayoutTests: XCTestCase {
    func testContinueButtonStaysWithinSafeAreaOnSmallScreen() throws {
        let (window, hosting) = try makeHostedQuickSetup(
            size: CGSize(width: 320, height: 568),
            safeAreaBottom: 34,
            step: .localeAndCurrencies
        )

        XCTAssertNotNil(window)

        let continueButton = try XCTUnwrap(hosting.view.findView(withAccessibilityIdentifier: "quickSetup.continueButton"))
        let continueFrame = continueButton.convert(continueButton.bounds, to: hosting.view)
        let safeFrame = hosting.view.safeAreaLayoutGuide.layoutFrame

        XCTAssertLessThanOrEqual(continueFrame.maxY, safeFrame.maxY + 1)
        XCTAssertGreaterThanOrEqual(continueFrame.minY, safeFrame.minY - 1)
        XCTAssertGreaterThan(continueFrame.height, 0)
    }

    func testContinueButtonStaysWithinSafeAreaOnExpenseCategoriesStepSmallScreen() throws {
        let (window, hosting) = try makeHostedQuickSetup(
            size: CGSize(width: 320, height: 568),
            safeAreaBottom: 34,
            step: .expenseCategories
        )

        XCTAssertNotNil(window)

        let continueButton = try XCTUnwrap(hosting.view.findView(withAccessibilityIdentifier: "quickSetup.continueButton"))
        let continueFrame = continueButton.convert(continueButton.bounds, to: hosting.view)
        let safeFrame = hosting.view.safeAreaLayoutGuide.layoutFrame

        XCTAssertLessThanOrEqual(continueFrame.maxY, safeFrame.maxY + 1)
    }

    func testProductFieldsArePresentOnProductsStep() throws {
        let (window, hosting) = try makeHostedQuickSetup(
            size: CGSize(width: 320, height: 568),
            safeAreaBottom: 34,
            step: .products
        )

        XCTAssertNotNil(window)

        XCTAssertNotNil(hosting.view.findView(withAccessibilityIdentifier: "quickSetup.productNameField"))
        XCTAssertNotNil(hosting.view.findView(withAccessibilityIdentifier: "quickSetup.productAmountField"))
    }

    // MARK: - Helpers

    private func makeHostedQuickSetup(
        size: CGSize,
        safeAreaBottom: CGFloat,
        step: QuickSetupStep
    ) throws -> (UIWindow, UIHostingController<AnyView>) {
        let schema = Schema([Item.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let suiteName = "QuickSetupLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let appState = AppState()
        let viewModel = QuickSetupViewModel(appState: appState, defaults: defaults)
        viewModel.currentStep = step

        let rootView = QuickSetupView(viewModel: viewModel, mode: .settings)
            .environment(appState)
            .modelContainer(container)
            .preferredColorScheme(.dark)

        let hosting = UIHostingController(rootView: AnyView(rootView))
        hosting.additionalSafeAreaInsets.bottom = safeAreaBottom

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = hosting
        window.makeKeyAndVisible()

        hosting.view.frame = window.bounds
        window.layoutIfNeeded()
        hosting.view.layoutIfNeeded()

        return (window, hosting)
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
