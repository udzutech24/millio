import EventKitUI
import SwiftUI

/// Thin bridge to Apple's editor. The system UI, not Millio, owns calendar selection and save.
struct AppleCalendarEventEditorSheet: UIViewControllerRepresentable {
    let eventStore: AppleCalendarEventStore
    let payload: AppleCalendarEventExportPayload
    let onCompletion: (EKEventEditViewAction) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = eventStore.eventStoreForEditor
        controller.event = eventStore.makeUnsavedEvent(from: payload)
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        private let onCompletion: (EKEventEditViewAction) -> Void

        init(onCompletion: @escaping (EKEventEditViewAction) -> Void) {
            self.onCompletion = onCompletion
        }

        func eventEditViewController(
            _ controller: EKEventEditViewController,
            didCompleteWith action: EKEventEditViewAction
        ) {
            controller.dismiss(animated: true) {
                self.onCompletion(action)
            }
        }
    }
}
