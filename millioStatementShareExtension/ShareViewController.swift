import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        statusLabel.text = "Saving to Millio…"
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24)
        ])
        processInput()
    }

    private func processInput() {
        let providers = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .compactMap(\.attachments)
            .flatMap { $0 } ?? []
        let accepted = providers.compactMap { provider -> (NSItemProvider, UTType)? in
            IncomingStatementFilePolicy.allowedTypes.first(where: {
                provider.hasItemConformingToTypeIdentifier($0.identifier)
            }).map { (provider, $0) }
        }
        guard accepted.count == 1, providers.count == 1 else {
            finish(error: IncomingStatementFileError.unsupportedType)
            return
        }
        let (provider, type) = accepted[0]
        provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { [weak self] url, error in
            guard let self, error == nil, let url else {
                DispatchQueue.main.async {
                    self?.finish(error: error ?? IncomingStatementFileError.missingFile)
                }
                return
            }
            do {
                _ = try IncomingStatementInbox.appGroup().enqueue(sourceURL: url, declaredType: type)
                DispatchQueue.main.async { self.finish(error: nil) }
            } catch {
                DispatchQueue.main.async { self.finish(error: error) }
            }
        }
    }

    private func finish(error: Error?) {
        if let error {
            statusLabel.text = "Could not save this statement."
            extensionContext?.cancelRequest(withError: error)
        } else {
            statusLabel.text = "Saved to Millio"
            extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
