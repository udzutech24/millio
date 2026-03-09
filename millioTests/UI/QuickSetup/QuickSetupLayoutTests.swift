import XCTest
import SwiftUI
import SwiftData
@testable import millio

@MainActor
final class QuickSetupLayoutTests: XCTestCase {
    func testContinueButtonStaysWithinSafeAreaOnSmallScreen() throws {
        let hosted = try makeHostedQuickSetup(
            size: CGSize(width: 320, height: 568),
            safeAreaBottom: 34,
            step: .localeAndCurrencies
        )

        XCTAssertNotNil(hosted.window)

        let scrollView = try XCTUnwrap(hosted.hosting.view.findHostingScrollView())
        let scrollFrame = scrollView.convert(scrollView.bounds, to: hosted.hosting.view)
        XCTAssertGreaterThan(scrollView.adjustedContentInset.bottom, 80)
        XCTAssertEqual(scrollFrame.maxY, hosted.hosting.view.bounds.maxY, accuracy: 1)
    }

    func testContinueButtonStaysWithinSafeAreaOnExpenseCategoriesStepSmallScreen() throws {
        let hosted = try makeHostedQuickSetup(
            size: CGSize(width: 320, height: 568),
            safeAreaBottom: 34,
            step: .expenseCategories
        )

        XCTAssertNotNil(hosted.window)

        let scrollView = try XCTUnwrap(hosted.hosting.view.findHostingScrollView())
        let scrollFrame = scrollView.convert(scrollView.bounds, to: hosted.hosting.view)
        XCTAssertGreaterThan(scrollView.adjustedContentInset.bottom, 80)
        XCTAssertEqual(scrollFrame.maxY, hosted.hosting.view.bounds.maxY, accuracy: 1)
    }

    func testProductFieldsArePresentOnProductsStep() throws {
        let hosted = try makeHostedQuickSetup(
            size: CGSize(width: 320, height: 568),
            safeAreaBottom: 34,
            step: .products
        )

        XCTAssertNotNil(hosted.window)
        XCTAssertEqual(hosted.viewModel.currentStep, .products)
        XCTAssertEqual(hosted.viewModel.productTypeForCreation, .card)
        XCTAssertFalse(hosted.viewModel.isMarketProductDraft)
        XCTAssertEqual(hosted.viewModel.productAmountFieldTitle, "Баланс в RUB")
    }

    // MARK: - Helpers

    private func makeHostedQuickSetup(
        size: CGSize,
        safeAreaBottom: CGFloat,
        step: QuickSetupStep
    ) throws -> HostedQuickSetup {
        let schema = Schema([Item.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let suiteName = "QuickSetupLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let appState = AppState()
        appState.selectedLanguage = .russian
        let systemContext = QuickSetupSystemContext(
            preferredLanguageIdentifiers: ["ru-RU"],
            locale: Locale(identifier: "ru_RU")
        )
        let viewModel = QuickSetupViewModel(
            appState: appState,
            systemContext: systemContext,
            defaults: defaults
        )
        viewModel.currentStep = step

        let rootView = QuickSetupView(viewModel: viewModel, mode: .settings)
            .environment(appState)
            .modelContainer(container)
            .preferredColorScheme(.dark)

        let hosting = UIHostingController(rootView: AnyView(rootView))
        hosting.additionalSafeAreaInsets.bottom = safeAreaBottom

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

        return HostedQuickSetup(window: window, hosting: hosting, viewModel: viewModel)
    }
}

private extension UIView {
    func findHostingScrollView() -> UIScrollView? {
        if let scrollView = self as? UIScrollView {
            return scrollView
        }
        for subview in subviews {
            if let scrollView = subview.findHostingScrollView() {
                return scrollView
            }
        }
        return nil
    }
}

private struct HostedQuickSetup {
    let window: UIWindow
    let hosting: UIHostingController<AnyView>
    let viewModel: QuickSetupViewModel
}
